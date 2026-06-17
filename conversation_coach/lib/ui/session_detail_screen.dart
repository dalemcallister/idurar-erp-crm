import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../data/models/analysis.dart';
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
  Analysis? _analysis;
  List<Segment> _segments = [];
  Map<String, Speaker> _speakers = {};
  List<Recommendation> _recommendations = [];
  Recording? _recording;

  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final session = await state.repo.session(widget.sessionId);
    final analysis = await state.repo.analysisForSession(widget.sessionId);
    final segments = await state.repo.segments(widget.sessionId);
    final speakers = await state.repo.speakerMap(widget.sessionId);
    final recs = await state.repo.recommendations(widget.sessionId);
    final recording = await state.repo.recordingForSession(widget.sessionId);
    if (!mounted) return;
    setState(() {
      _session = session;
      _analysis = analysis;
      _segments = segments;
      _speakers = speakers;
      _recommendations = recs;
      _recording = recording;
    });

    // While the background pipeline runs, poll until the report is ready.
    if (session != null &&
        session.status != SessionStatus.ready &&
        session.status != SessionStatus.failed) {
      _poll ??= Timer.periodic(
          const Duration(seconds: 2), (_) => _load());
    } else {
      _poll?.cancel();
      _poll = null;
    }
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
                    _recommendations),
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
                      speakers: _speakers),
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
            : _ProcessingState(status: session.status),
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
  const _ProcessingState({required this.status});

  @override
  Widget build(BuildContext context) {
    if (status == SessionStatus.failed) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Color(0xFFB44A3F)),
              SizedBox(height: 16),
              Text(
                'Analysis failed. Check your model/provider settings and try '
                'recording again.',
                textAlign: TextAlign.center,
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
