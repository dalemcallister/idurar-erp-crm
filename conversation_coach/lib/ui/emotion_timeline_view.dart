import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../data/models/analysis.dart';
import '../data/models/speaker.dart';

/// Emotion & dynamics timeline (Design §6.5) — talk-time ratio, interruptions,
/// pace and energy, plus an emotional-arc line per speaker.
class EmotionTimelineView extends StatelessWidget {
  final Analysis analysis;
  final Map<String, Speaker> speakers;

  const EmotionTimelineView({
    super.key,
    required this.analysis,
    required this.speakers,
  });

  static const _palette = [
    Color(0xFF2E6F6A),
    Color(0xFFB8860B),
    Color(0xFF6A4C93),
    Color(0xFFB44A3F),
  ];

  String _label(String speakerId) =>
      speakers[speakerId]?.label ?? speakerId;

  @override
  Widget build(BuildContext context) {
    final d = analysis.dynamics;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _DynamicsCard(dynamics: d, label: _label),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Emotional arc',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('Valence over the session (higher = more positive).',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 16),
                SizedBox(height: 220, child: _arcChart()),
                const SizedBox(height: 12),
                _legend(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _arcChart() {
    final bySpeaker = <String, List<EmotionPoint>>{};
    for (final p in analysis.emotionArc) {
      bySpeaker.putIfAbsent(p.speakerId, () => []).add(p);
    }
    if (bySpeaker.isEmpty) {
      return const Center(child: Text('No emotion data for this session.'));
    }

    final maxMs = analysis.emotionArc
        .map((e) => e.atMs)
        .fold<int>(1, (a, b) => a > b ? a : b);

    final lines = <LineChartBarData>[];
    var idx = 0;
    for (final entry in bySpeaker.entries) {
      final color = _palette[idx % _palette.length];
      idx++;
      lines.add(LineChartBarData(
        isCurved: true,
        color: color,
        barWidth: 2.5,
        dotData: FlDotData(show: false),
        spots: [
          for (final p in entry.value)
            FlSpot(p.atMs / maxMs, p.valence.clamp(-1, 1)),
        ],
      ));
    }

    return LineChart(
      LineChartData(
        minY: -1,
        maxY: 1,
        gridData: FlGridData(show: true, drawVerticalLine: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (v, _) {
                if (v == 1) return const Text('＋', style: TextStyle(fontSize: 12));
                if (v == 0) return const Text('0', style: TextStyle(fontSize: 12));
                if (v == -1) return const Text('－', style: TextStyle(fontSize: 12));
                return const SizedBox.shrink();
              },
            ),
          ),
          rightTitles:
              AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                if (v == 0) return const Text('start', style: TextStyle(fontSize: 10));
                if (v >= 0.98) return const Text('end', style: TextStyle(fontSize: 10));
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: lines,
      ),
    );
  }

  Widget _legend() {
    final ids = analysis.emotionArc.map((e) => e.speakerId).toSet().toList();
    return Wrap(
      spacing: 16,
      children: [
        for (var i = 0; i < ids.length; i++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                      color: _palette[i % _palette.length],
                      shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(_label(ids[i])),
            ],
          ),
      ],
    );
  }
}

class _DynamicsCard extends StatelessWidget {
  final Dynamics dynamics;
  final String Function(String speakerId) label;
  const _DynamicsCard({required this.dynamics, required this.label});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Conversation dynamics',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            if (dynamics.talkTimeRatio.isNotEmpty) ...[
              const Text('Talk-time ratio', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 6),
              _TalkTimeBar(ratios: dynamics.talkTimeRatio, label: label),
              const SizedBox(height: 16),
            ],
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _stat('Interruptions', dynamics.interruptions.toString(),
                    Icons.front_hand_outlined),
                _stat('Questions', dynamics.questionCount.toString(),
                    Icons.help_outline),
                _stat(
                    'Longest monologue',
                    '${(dynamics.longestMonologueMs / 1000).round()}s',
                    Icons.timer_outlined),
                _stat('Filler rate',
                    '${dynamics.fillerWordRate.toStringAsFixed(1)}/100w',
                    Icons.bubble_chart_outlined),
                _stat(
                    'Avg response',
                    '${(dynamics.avgResponseLatencyMs / 1000).toStringAsFixed(1)}s',
                    Icons.schedule),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.black54),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              Text(label,
                  style: const TextStyle(fontSize: 11, color: Colors.black54)),
            ],
          ),
        ],
      ),
    );
  }
}

class _TalkTimeBar extends StatelessWidget {
  final Map<String, double> ratios;
  final String Function(String) label;
  const _TalkTimeBar({required this.ratios, required this.label});

  static const _palette = EmotionTimelineView._palette;

  @override
  Widget build(BuildContext context) {
    final entries = ratios.entries.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Row(
            children: [
              for (var i = 0; i < entries.length; i++)
                Expanded(
                  flex: (entries[i].value * 1000).round().clamp(1, 1000),
                  child: Container(
                    height: 18,
                    color: _palette[i % _palette.length],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          children: [
            for (var i = 0; i < entries.length; i++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      width: 12,
                      height: 12,
                      color: _palette[i % _palette.length]),
                  const SizedBox(width: 6),
                  Text(
                      '${label(entries[i].key)} ${(entries[i].value * 100).round()}%'),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
