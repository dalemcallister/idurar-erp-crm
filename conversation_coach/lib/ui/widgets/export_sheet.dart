import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/models/analysis.dart';
import '../../data/models/goal.dart';
import '../../data/models/recommendation.dart';
import '../../data/models/segment.dart';
import '../../data/models/session.dart';
import '../../data/models/speaker.dart';
import 'follow_up_email.dart';

/// Export a session as a Markdown report plus transcript (F-DAT-01). The report
/// can be copied to the clipboard or written to a file in the app documents
/// directory. (Audio export and PDF rendering are follow-on work.)
Future<void> showExportSheet(
  BuildContext context,
  Session session,
  Analysis analysis,
  List<Segment> segments,
  Map<String, Speaker> speakers,
  List<Recommendation> recommendations, {
  Goal? goal,
}) async {
  final markdown = _buildMarkdown(
      session, analysis, segments, speakers, recommendations);

  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            leading: Icon(Icons.ios_share),
            title: Text('Export session'),
            subtitle: Text('Markdown report + transcript'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.email_outlined),
            title: const Text('Send action steps as email'),
            subtitle: const Text('Opens your mail app with a follow-up draft'),
            onTap: () {
              Navigator.pop(ctx);
              sendFollowUpEmail(context, session, analysis, goal);
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('Copy to clipboard'),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: markdown));
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Report copied.')));
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.save_alt),
            title: const Text('Save as .md file'),
            onTap: () async {
              final path = await _writeFile(session, markdown);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Saved to $path')));
              }
            },
          ),
        ],
      ),
    ),
  );
}

Future<String> _writeFile(Session session, String markdown) async {
  final dir = await getApplicationDocumentsDirectory();
  final exportDir = Directory(p.join(dir.path, 'exports'));
  if (!await exportDir.exists()) await exportDir.create(recursive: true);
  final file = File(p.join(exportDir.path, '${session.id}.md'));
  await file.writeAsString(markdown);
  return file.path;
}

String _buildMarkdown(
  Session session,
  Analysis a,
  List<Segment> segments,
  Map<String, Speaker> speakers,
  List<Recommendation> recs,
) {
  final b = StringBuffer();
  b.writeln('# ${session.title}');
  b.writeln();
  b.writeln('*${DateFormat.yMMMMd().add_jm().format(session.createdAt)} · '
      '${session.durationSec ~/ 60}m ${session.durationSec % 60}s · '
      '${session.providerConfigSnapshot.isEmpty ? a.modelUsed : session.providerConfigSnapshot}*');
  b.writeln();
  b.writeln('## Headline');
  b.writeln(a.headline);
  b.writeln();
  b.writeln('**Goal score: ${a.scoreOverall.round()}/100**');
  b.writeln();
  for (final d in a.scoreByDimension) {
    b.writeln('- ${d.dimension}: ${d.score.round()} — ${d.rationale}');
  }
  b.writeln();
  if (a.strengths.isNotEmpty) {
    b.writeln('## Strengths');
    for (final s in a.strengths) {
      b.writeln('- $s');
    }
    b.writeln();
  }
  if (a.improvements.isNotEmpty) {
    b.writeln('## Improvements');
    for (final s in a.improvements) {
      b.writeln('- $s');
    }
    b.writeln();
  }
  if (recs.isNotEmpty) {
    b.writeln('## Recommendations');
    for (final r in recs) {
      b.writeln('${r.priority}. ${r.text}');
      if (r.whatToTryInstead != null && r.whatToTryInstead!.isNotEmpty) {
        b.writeln('   - *Try instead:* "${r.whatToTryInstead}"');
      }
    }
    b.writeln();
  }
  if (a.nextSteps.isNotEmpty) {
    b.writeln('## Your next steps');
    for (var i = 0; i < a.nextSteps.length; i++) {
      b.writeln('${i + 1}. ${a.nextSteps[i]}');
    }
    b.writeln();
  }
  if (a.actionItems.isNotEmpty) {
    b.writeln('## Action items');
    for (final s in a.actionItems) {
      b.writeln('- [ ] $s');
    }
    b.writeln();
  }
  b.writeln('## Transcript');
  for (final s in segments) {
    final sp = speakers[s.speakerId]?.label ?? 'Speaker';
    b.writeln('**[${s.timestampLabel()}] $sp:** ${s.text}');
    b.writeln();
  }
  return b.toString();
}
