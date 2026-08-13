import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/analysis.dart';
import '../../data/models/goal.dart';
import '../../data/models/session.dart';

/// Builds and sends a follow-up "action steps" email for a session. There is no
/// backend — this opens the device's own mail composer (mailto:) with the
/// subject and body pre-filled, so the user reviews and sends it from their
/// account. If no mail app is available the text is copied to the clipboard.

String followUpSubject(Session session, Goal? goal) {
  final what = goal?.name ?? session.title;
  return 'Follow-up & next steps — $what';
}

String followUpBody(Session session, Analysis analysis, Goal? goal) {
  final b = StringBuffer();
  final date = DateFormat.yMMMMd().format(session.createdAt);
  b.writeln('Hi,');
  b.writeln();
  b.writeln('Thanks for the conversation'
      '${goal == null ? '' : ' about ${goal.name.toLowerCase()}'} on $date. '
      'Here is a short recap and the next steps.');
  b.writeln();

  if (analysis.headline.isNotEmpty) {
    b.writeln('Recap:');
    b.writeln(analysis.headline);
    b.writeln();
  }

  // Prefer the tailored next steps; fall back to raw action items.
  final steps =
      analysis.nextSteps.isNotEmpty ? analysis.nextSteps : analysis.actionItems;
  if (steps.isNotEmpty) {
    b.writeln('Next steps:');
    for (var i = 0; i < steps.length; i++) {
      b.writeln('${i + 1}. ${steps[i]}');
    }
    b.writeln();
  }

  if (analysis.decisions.isNotEmpty) {
    b.writeln('Decisions:');
    for (final d in analysis.decisions) {
      b.writeln('- $d');
    }
    b.writeln();
  }

  if (analysis.openQuestions.isNotEmpty) {
    b.writeln('Open questions:');
    for (final q in analysis.openQuestions) {
      b.writeln('- $q');
    }
    b.writeln();
  }

  b.writeln('Best regards,');
  b.writeln();
  b.writeln('— Prepared with Conversation Coach');
  return b.toString();
}

/// Percent-encodes mailto query parameters (spaces as %20, not +).
String _encodeMailtoQuery(Map<String, String> params) => params.entries
    .map((e) =>
        '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
    .join('&');

Future<void> sendFollowUpEmail(
  BuildContext context,
  Session session,
  Analysis analysis,
  Goal? goal,
) async {
  final subject = followUpSubject(session, goal);
  final body = followUpBody(session, analysis, goal);
  final uri = Uri(
    scheme: 'mailto',
    query: _encodeMailtoQuery({'subject': subject, 'body': body}),
  );

  var launched = false;
  try {
    launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    launched = false;
  }

  if (!launched && context.mounted) {
    // No mail app resolved the intent — hand the text back via the clipboard.
    await Clipboard.setData(ClipboardData(text: '$subject\n\n$body'));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'No mail app found — the follow-up was copied to your clipboard.')));
    }
  }
}
