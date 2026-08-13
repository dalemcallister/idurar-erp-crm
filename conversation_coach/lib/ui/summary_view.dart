import 'package:flutter/material.dart';

import '../core/pricing.dart';
import '../core/theme.dart';
import '../data/models/analysis.dart';
import '../data/models/goal.dart';
import '../data/models/session.dart';
import '../data/models/speaker.dart';
import 'widgets/follow_up_email.dart';

/// Session detail — summary (Design §6.3). Opens on the headline, then the goal
/// score, top strengths and improvements. Numbers support the narrative.
class SummaryView extends StatelessWidget {
  final Session session;
  final Analysis analysis;
  final Map<String, Speaker> speakers;
  final Goal? goal;

  const SummaryView({
    super.key,
    required this.session,
    required this.analysis,
    required this.speakers,
    this.goal,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(analysis.headline,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(height: 1.3, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        _ScoreCard(analysis: analysis),
        if (analysis.inputTokens > 0 || analysis.outputTokens > 0)
          _CostCard(analysis: analysis),
        const SizedBox(height: 8),
        _NextStepsCard(session: session, analysis: analysis, goal: goal),
        _ListCard(
          title: 'Top strengths',
          icon: Icons.thumb_up_alt_outlined,
          color: const Color(0xFF2E7D5B),
          items: analysis.strengths,
        ),
        _ListCard(
          title: 'Top improvements',
          icon: Icons.trending_up,
          color: const Color(0xFFB8860B),
          items: analysis.improvements,
        ),
        if (analysis.summary.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Summary',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(analysis.summary),
                ],
              ),
            ),
          ),
        if (analysis.topics.isNotEmpty)
          _ChipsCard(title: 'Key topics', items: analysis.topics),
        if (analysis.actionItems.isNotEmpty)
          _ListCard(
            title: 'Action items',
            icon: Icons.checklist,
            color: Theme.of(context).colorScheme.primary,
            items: analysis.actionItems,
          ),
        if (analysis.openQuestions.isNotEmpty)
          _ListCard(
            title: 'Open / unanswered questions',
            icon: Icons.help_outline,
            color: Colors.indigo,
            items: analysis.openQuestions,
          ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'Analyzed with ${session.providerConfigSnapshot.isEmpty ? analysis.modelUsed : session.providerConfigSnapshot} · prompt ${analysis.promptVersion}',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

/// "Your next steps" — the concrete follow-up actions for the user after the
/// conversation, with a one-tap button to send them as an email from the
/// device's own mail app (no backend).
class _NextStepsCard extends StatelessWidget {
  final Session session;
  final Analysis analysis;
  final Goal? goal;
  const _NextStepsCard({
    required this.session,
    required this.analysis,
    required this.goal,
  });

  @override
  Widget build(BuildContext context) {
    // Prefer the tailored next steps; fall back to raw action items so the card
    // still appears when a model only returned action items.
    final steps = analysis.nextSteps.isNotEmpty
        ? analysis.nextSteps
        : analysis.actionItems;
    if (steps.isEmpty) return const SizedBox.shrink();

    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      color: const Color(0xFFF0F5F4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.checklist_rtl, size: 18, color: primary),
              const SizedBox(width: 8),
              const Text('Your next steps',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 4),
            const Text(
              'Recommended actions to follow up on this conversation.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Text('${i + 1}',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: primary)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(steps[i])),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () =>
                    sendFollowUpEmail(context, session, analysis, goal),
                icon: const Icon(Icons.email_outlined),
                label: const Text('Email these steps'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Per-session token & cost meter (F-MOD-06). Shows the analysis call's token
/// usage and an estimated cost for the model used.
class _CostCard extends StatelessWidget {
  final Analysis analysis;
  const _CostCard({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final total = analysis.inputTokens + analysis.outputTokens;
    final cost = Pricing.estimateCost(
        analysis.modelUsed, analysis.inputTokens, analysis.outputTokens);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.savings_outlined, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Analysis cost',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    '$total tokens · ${analysis.inputTokens} in / '
                    '${analysis.outputTokens} out',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Text(
              cost == null ? '—' : Pricing.formatUsd(cost),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  final Analysis analysis;
  const _ScoreCard({required this.analysis});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                _ScoreRing(score: analysis.scoreOverall),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Goal score',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(
                        'Scored against your chosen rubric, with evidence per '
                        'dimension below.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final d in analysis.scoreByDimension) _dimensionRow(context, d),
          ],
        ),
      ),
    );
  }

  Widget _dimensionRow(BuildContext context, DimensionScore d) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(d.dimension,
                      style: const TextStyle(fontWeight: FontWeight.w500))),
              Text('${d.score.round()}',
                  style: TextStyle(
                      color: CoachTheme.scoreColor(d.score),
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: d.score / 100,
              minHeight: 6,
              backgroundColor: Colors.black12,
              valueColor:
                  AlwaysStoppedAnimation(CoachTheme.scoreColor(d.score)),
            ),
          ),
          if (d.rationale.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(d.rationale,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}

class _ScoreRing extends StatelessWidget {
  final double score;
  const _ScoreRing({required this.score});

  @override
  Widget build(BuildContext context) {
    final color = CoachTheme.scoreColor(score);
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: CircularProgressIndicator(
              value: score / 100,
              strokeWidth: 7,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          Text(score.round().toString(),
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

class _ListCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<String> items;
  const _ListCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 8),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: TextStyle(color: color)),
                    Expanded(child: Text(item)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChipsCard extends StatelessWidget {
  final String title;
  final List<String> items;
  const _ChipsCard({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [for (final t in items) Chip(label: Text(t))],
            ),
          ],
        ),
      ),
    );
  }
}
