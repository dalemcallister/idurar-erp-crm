import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/theme.dart';
import '../data/models/analysis.dart';
import '../data/models/session.dart';
import 'session_detail_screen.dart';

/// Searchable list of past sessions (Design §5 — Sessions area).
class SessionsListScreen extends StatefulWidget {
  const SessionsListScreen({super.key});

  @override
  State<SessionsListScreen> createState() => _SessionsListScreenState();
}

class _SessionsListScreenState extends State<SessionsListScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Sessions')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search sessions',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Session>>(
              future: state.sessions(query: _query),
              builder: (context, snap) {
                final sessions = snap.data ?? const [];
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (sessions.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                          'No sessions yet. Tap Record to capture your first one.',
                          textAlign: TextAlign.center),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: sessions.length,
                  itemBuilder: (context, i) =>
                      _SessionTile(session: sessions[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final Session session;
  const _SessionTile({required this.session});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Card(
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          title: Text(session.title,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${DateFormat.yMMMd().add_jm().format(session.createdAt)} · '
            '${_duration(session.durationSec)}',
          ),
          trailing: FutureBuilder<Analysis?>(
            future: state.repo.analysisForSession(session.id),
            builder: (context, snap) {
              if (session.status.isBusy) {
                return _StatusChip(session.status.label,
                    color: Theme.of(context).colorScheme.primary);
              }
              final a = snap.data;
              if (a == null) {
                return _StatusChip(session.status.label,
                    color: Colors.grey);
              }
              return CircleAvatar(
                radius: 20,
                backgroundColor:
                    CoachTheme.scoreColor(a.scoreOverall).withValues(alpha: 0.15),
                child: Text(
                  a.scoreOverall.round().toString(),
                  style: TextStyle(
                    color: CoachTheme.scoreColor(a.scoreOverall),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            },
          ),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SessionDetailScreen(sessionId: session.id),
          )),
        ),
      ),
    );
  }

  String _duration(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip(this.label, {required this.color});

  @override
  Widget build(BuildContext context) => Chip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        backgroundColor: color.withValues(alpha: 0.12),
        labelStyle: TextStyle(color: color),
        visualDensity: VisualDensity.compact,
        side: BorderSide.none,
      );
}
