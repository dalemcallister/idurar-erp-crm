import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../audio/audio_capture.dart';
import '../core/app_state.dart';
import '../core/pricing.dart';
import '../data/models/session.dart';
import 'session_detail_screen.dart';

/// Live recording — large timer, live input-level meter, a prominent recording
/// indicator, pause/resume, and "mark moment" (Design §6.2, F-CAP-05/06).
class LiveRecordingScreen extends StatefulWidget {
  final Session session;
  final MicInput device;

  const LiveRecordingScreen({
    super.key,
    required this.session,
    required this.device,
  });

  @override
  State<LiveRecordingScreen> createState() => _LiveRecordingScreenState();
}

class _LiveRecordingScreenState extends State<LiveRecordingScreen> {
  final _capture = AudioCapture();
  final _uuid = const Uuid();

  Duration _elapsed = Duration.zero;
  double _level = 0;
  bool _paused = false;
  bool _stopping = false;
  int _marks = 0;
  String? _audioPath;

  StreamSubscription<Duration>? _elapsedSub;
  StreamSubscription<double>? _levelSub;

  @override
  void initState() {
    super.initState();
    _begin();
  }

  Future<void> _begin() async {
    final dir = await getApplicationDocumentsDirectory();
    final audioDir = Directory(p.join(dir.path, 'recordings'));
    if (!await audioDir.exists()) await audioDir.create(recursive: true);
    _audioPath = p.join(audioDir.path, '${widget.session.id}.wav');

    _elapsedSub = _capture.elapsed.listen((d) {
      if (mounted) setState(() => _elapsed = d);
    });
    _levelSub = _capture.amplitude.listen((a) {
      if (mounted) setState(() => _level = a);
    });

    try {
      await _capture.start(filePath: _audioPath!, device: widget.device);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not start recording: $e')));
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _togglePause() async {
    if (_paused) {
      await _capture.resume();
    } else {
      await _capture.pause();
    }
    setState(() => _paused = !_paused);
  }

  void _mark() {
    _capture.markMoment();
    setState(() => _marks++);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('Moment marked at ${_fmt(_elapsed)}'),
          duration: const Duration(seconds: 1)),
    );
  }

  Future<void> _stop() async {
    if (_stopping) return;
    setState(() => _stopping = true);
    final state = context.read<AppState>();

    final recording = await _capture.stop(
      sessionId: widget.session.id,
      id: 'rec-${_uuid.v4()}',
    );
    final duration = _capture.totalDuration();

    final session = widget.session
      ..durationSec = duration.inSeconds
      ..status = SessionStatus.recorded;
    await state.repo.upsertSession(session);
    await state.repo.upsertRecording(recording);

    // Kick off transcription + analysis in the background; the detail screen
    // shows progress and updates when ready.
    _runPipeline(state, session, recording.encryptedPath);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => SessionDetailScreen(sessionId: session.id),
    ));
  }

  Future<void> _runPipeline(
      AppState state, Session session, String audioPath) async {
    try {
      final goal = await state.repo.goal(session.goalId);
      final rubric =
          goal == null ? null : await state.repo.rubric(goal.rubricId);
      if (goal == null || rubric == null) {
        debugPrint('[PIPELINE] missing goal/rubric for ${session.goalId} '
            '-> marking failed');
        await state.repo.updateSessionStatus(session.id, SessionStatus.failed);
        return;
      }
      final engine = await state.transcriptionEngine();
      final analysis = await state.orchestrator.run(
        session: session,
        goal: goal,
        rubric: rubric,
        transcriptionEngine: engine,
        providerConfig: state.preferredProvider,
        audioPath: audioPath,
      );
      // Draw the estimated cost down from the prepaid budget (F-MOD-06).
      final cost = Pricing.estimateCost(
          analysis.modelUsed, analysis.inputTokens, analysis.outputTokens);
      if (cost != null) await state.recordSpend(cost);
    } catch (e, st) {
      debugPrint('[PIPELINE] FAILED for ${session.id}: $e\n$st');
      await state.repo.updateSessionStatus(session.id, SessionStatus.failed);
    }
  }

  @override
  void dispose() {
    _elapsedSub?.cancel();
    _levelSub?.cancel();
    _capture.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF1C2422),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _recordingIndicator(),
                const Spacer(),
                Center(
                  child: Text(
                    _fmt(_elapsed),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 64,
                        fontFeatures: [],
                        fontWeight: FontWeight.w300),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    widget.device.isUsb
                        ? '${widget.device.label} · USB-C · 48 kHz'
                        : widget.device.label,
                    style: const TextStyle(color: Colors.white60),
                  ),
                ),
                const SizedBox(height: 32),
                _LevelMeter(level: _level, channels: widget.device.isUsb ? 2 : 1),
                const Spacer(),
                if (_marks > 0)
                  Center(
                    child: Text('$_marks moment${_marks == 1 ? '' : 's'} marked',
                        style: const TextStyle(color: Colors.white54)),
                  ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _circleButton(
                      icon: _paused ? Icons.play_arrow : Icons.pause,
                      label: _paused ? 'Resume' : 'Pause',
                      onTap: _stopping ? null : _togglePause,
                    ),
                    _circleButton(
                      icon: Icons.stop,
                      label: 'Stop',
                      color: const Color(0xFFB44A3F),
                      onTap: _stopping ? null : _stop,
                    ),
                    _circleButton(
                      icon: Icons.flag,
                      label: 'Mark',
                      onTap: _stopping || _paused ? null : _mark,
                    ),
                  ],
                ),
                if (_stopping)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Center(
                      child: Text('Saving…',
                          style: TextStyle(color: Colors.white70)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _recordingIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _paused ? Colors.white38 : const Color(0xFFE53935),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _paused ? 'PAUSED' : 'RECORDING',
          style: const TextStyle(
              color: Colors.white, letterSpacing: 2, fontSize: 13),
        ),
      ],
    );
  }

  Widget _circleButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    Color? color,
  }) {
    return Column(
      children: [
        Material(
          color: color ?? Colors.white12,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

/// Live input-level meter, one bar per channel (Design §6.2). With a
/// two-transmitter USB kit each speaker shows on a separate channel.
class _LevelMeter extends StatelessWidget {
  final double level;
  final int channels;
  const _LevelMeter({required this.level, required this.channels});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var c = 0; c < channels; c++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                    width: 28,
                    child: Text('CH${c + 1}',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11))),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: level,
                      minHeight: 10,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation(
                        level > 0.85
                            ? const Color(0xFFE53935)
                            : const Color(0xFF4DB6AC),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
