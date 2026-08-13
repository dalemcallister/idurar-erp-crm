import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../data/models/analysis.dart';
import '../data/models/goal.dart';
import '../data/models/recommendation.dart';
import '../data/models/recording.dart';
import '../data/models/segment.dart';
import '../data/models/session.dart';
import '../data/models/speaker.dart';
import 'ask_view.dart';
import 'emotion_timeline_view.dart';
import 'recommendations_view.dart';
import 'summary_view.dart';
import 'transcript_view.dart';
import 'widgets/export_sheet.dart';

/// Session detail — summary, transcript, emotion timeline, recommendations and
/// the per-session Ask (Design §6.3–6.7). Opens on the summary headline.
class SessionDetailScreen extends StatefulWidget {
  final String sessionId;
  const SessionDetailScreen({super.key, required this.sessionId});

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  final _player = AudioPlayer();

  Session? _session;
  Goal? _goal;
  Analysis? _analysis;
  List<Segment> _segments = [];
  Map<String, Speaker> _speakers = {};
  List<Recommendation> _recommendations = [];
  Recording? _recording;
  Object? _loadError;

  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    // Load the session first and render the shell immediately, so a later
    // read/parse error can't blank the whole screen into a spinner.
    final session = await state.repo.session(widget.sessionId);
    if (!mounted) return;
    setState(() => _session = session);
    if (session == null) return;
    final goal = await state.repo.goal(session.goalId);
    if (mounted) setState(() => _goal = goal);

    try {
      final analysis = await state.repo.analysisForSession(widget.sessionId);
      final segments = await state.repo.segments(widget.sessionId);
      final speakers = await state.repo.speakerMap(widget.sessionId);
      final recs = await state.repo.recommendations(widget.sessionId);
      final recording =
          await state.repo.recordingForSession(widget.sessionId);
      if (!mounted) return;
      setState(() {
        _analysis = analysis;
        _segments = segments;
        _speakers = speakers;
        _recommendations = recs;
        _recording = recording;
        _loadError = null;
      });
    } catch (e, st) {
      debugPrint('SessionDetail _load failed for ${widget.sessionId}: $e\n$st');
      if (mounted) setState(() => _loadError = e);
    }

    // While the background pipeline runs, poll until the report is ready.
    if (session.status != SessionStatus.ready &&
        session.status != SessionStatus.failed) {
      _poll ??= Timer.periodic(
          const Duration(seconds: 2), (_) => _load());
    } else {
      _poll?.cancel();
      _poll = null;
    }
  }

  /// Re-runs transcription + analysis on the audio already on disk — used to
  /// recover a session that failed transiently (e.g. a network/transcription
  /// error) without having to record it again.
  Future<void> _retryAnalysis() async {
    final state = context.read<AppState>();
    final session = _session;
    if (session == null) return;
    final rec = _recording ??
        await state.repo.recordingForSession(widget.sessionId);
    if (rec == null || !await File(rec.encryptedPath).exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('The recording is no longer on this device, so '
                'analysis can’t be retried.')));
      }
      return;
    }
    // Flip the UI back into processing and re-run in the background.
    await state.repo.updateSessionStatus(session.id, SessionStatus.transcribing);
    state.runAnalysisPipeline(session, rec.encryptedPath);
    if (!mounted) return;
    setState(() {
      _session = session..status = SessionStatus.transcribing;
      _loadError = null;
    });
    _poll ??= Timer.periodic(const Duration(seconds: 2), (_) => _load());
  }

  Future<void> _playFrom(int ms) async {
    final rec = _recording;
    if (rec == null) return;
    final file = File(rec.encryptedPath);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Audio for this session is no longer stored.')));
      }
      return;
    }
    await _player.play(DeviceFileSource(rec.encryptedPath));
    await _player.seek(Duration(milliseconds: ms));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final ready = session.status == SessionStatus.ready && _analysis != null;

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text(session.title, overflow: TextOverflow.ellipsis),
          actions: [
            if (ready)
              IconButton(
                icon: const Icon(Icons.ios_share),
                tooltip: 'Export',
                onPressed: () => showExportSheet(
                    context, session, _analysis!, _segments, _speakers,
                    _recommendations,
                    goal: _goal),
              ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete session',
              onPressed: _confirmDelete,
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Summary'),
              Tab(text: 'Transcript'),
              Tab(text: 'Timeline'),
              Tab(text: 'Coaching'),
              Tab(text: 'Ask'),
            ],
          ),
        ),
        body: ready
            ? TabBarView(
                children: [
                  SummaryView(
                      session: session,
                      analysis: _analysis!,
                      speakers: _speakers,
                      goal: _goal),
                  TranscriptView(
                    session: session,
                    segments: _segments,
                    speakers: _speakers,
                    recording: _recording,
                    onPlay: _playFrom,
                    onChanged: _load,
                  ),
                  EmotionTimelineView(
                      analysis: _analysis!, speakers: _speakers),
                  RecommendationsView(
                      recommendations: _recommendations,
                      segments: _segments,
                      onPlay: _playFrom),
                  AskView(sessionId: session.id),
                ],
              )
            : _ProcessingState(
                status: session.status,
                loadError: _loadError,
                onRetry: () {
                  setState(() => _loadError = null);
                  _load();
                },
                onRetryAnalysis: _retryAnalysis,
              ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this session?'),
        content: const Text(
            'The recording, transcript and analysis will be permanently '
            'deleted. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<AppState>().repo.deleteSession(widget.sessionId);
      if (mounted) Navigator.of(context).pop();
    }
  }
}

class _ProcessingState extends StatelessWidget {
  final SessionStatus status;
  final Object? loadError;
  final VoidCallback? onRetry;
  final VoidCallback? onRetryAnalysis;
  const _ProcessingState({
    required this.status,
    this.loadError,
    this.onRetry,
    this.onRetryAnalysis,
  });

  @override
  Widget build(BuildContext context) {
    // The session is finished but the report couldn't be read/parsed back.
    // Surface the real error instead of spinning forever.
    if (loadError != null ||
        (status == SessionStatus.ready)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 48, color: Color(0xFFB44A3F)),
              const SizedBox(height: 16),
              const Text(
                'This session finished, but its report could not be loaded.',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              if (loadError != null) ...[
                const SizedBox(height: 8),
                Text('$loadError',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black54)),
              ],
              const SizedBox(height: 16),
              if (onRetry != null)
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
            ],
          ),
        ),
      );
    }
    if (status == SessionStatus.failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 48, color: Color(0xFFB44A3F)),
              const SizedBox(height: 16),
              const Text(
                "Analysis couldn't complete. The recording is kept — make sure "
                'your provider keys are set, then retry on the same audio (no '
                'need to re-record).',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              if (onRetryAnalysis != null)
                FilledButton.icon(
                  onPressed: onRetryAnalysis,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry analysis'),
                ),
            ],
          ),
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(status == SessionStatus.transcribing
              ? 'Transcribing the conversation…'
              : 'Analysing against your goal…'),
          const SizedBox(height: 8),
          const Text('This runs in the background — you can leave this screen.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ),
    );
  }
}
