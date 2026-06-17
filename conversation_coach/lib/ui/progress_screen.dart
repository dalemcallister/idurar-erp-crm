import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/theme.dart';
import '../data/models/analysis.dart';

/// Progress & trends (Design §5, F-PRO-01) — trend charts for chosen metrics
/// across sessions. Lets the user see, e.g., talk-time ratio improving.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

enum _Metric { goalScore, talkTime, fillerRate, questions }

class _ProgressScreenState extends State<ProgressScreen> {
  _Metric _metric = _Metric.goalScore;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: FutureBuilder<List<Analysis>>(
        future: state.repo.allAnalyses(),
        builder: (context, snap) {
          final analyses = snap.data ?? const [];
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (analyses.length < 2) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Record a couple of sessions to see your trends here.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SegmentedButton<_Metric>(
                segments: const [
                  ButtonSegment(value: _Metric.goalScore, label: Text('Score')),
                  ButtonSegment(value: _Metric.talkTime, label: Text('Talk %')),
                  ButtonSegment(value: _Metric.fillerRate, label: Text('Filler')),
                  ButtonSegment(
                      value: _Metric.questions, label: Text('Questions')),
                ],
                selected: {_metric},
                onSelectionChanged: (s) => setState(() => _metric = s.first),
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_metricLabel(),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('Across ${analyses.length} sessions',
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 16),
                      SizedBox(height: 240, child: _chart(analyses)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _trendNote(analyses),
            ],
          );
        },
      ),
    );
  }

  String _metricLabel() {
    switch (_metric) {
      case _Metric.goalScore:
        return 'Goal score';
      case _Metric.talkTime:
        return 'Your talk-time %';
      case _Metric.fillerRate:
        return 'Filler-word rate (per 100 words)';
      case _Metric.questions:
        return 'Questions asked';
    }
  }

  double _value(Analysis a) {
    switch (_metric) {
      case _Metric.goalScore:
        return a.scoreOverall;
      case _Metric.talkTime:
        // The user's share is the largest in most coaching sessions; use the
        // first speaker's ratio as the user's by convention.
        final ratios = a.dynamics.talkTimeRatio.values.toList();
        return ratios.isEmpty ? 0 : ratios.first * 100;
      case _Metric.fillerRate:
        return a.dynamics.fillerWordRate;
      case _Metric.questions:
        return a.dynamics.questionCount.toDouble();
    }
  }

  Widget _chart(List<Analysis> analyses) {
    final spots = <FlSpot>[];
    for (var i = 0; i < analyses.length; i++) {
      spots.add(FlSpot(i.toDouble(), _value(analyses[i])));
    }
    final maxY = spots.map((s) => s.y).fold<double>(10, (a, b) => a > b ? a : b);
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: (maxY * 1.2).ceilToDouble(),
        gridData: FlGridData(show: true, drawVerticalLine: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 36)),
          rightTitles:
              AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (v, _) => Text('S${v.toInt() + 1}',
                  style: const TextStyle(fontSize: 10)),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            isCurved: true,
            color: CoachTheme.seed,
            barWidth: 3,
            dotData: FlDotData(show: true),
            belowBarData: BarAreaData(
                show: true, color: CoachTheme.seed.withValues(alpha: 0.12)),
            spots: spots,
          ),
        ],
      ),
    );
  }

  Widget _trendNote(List<Analysis> analyses) {
    final first = _value(analyses.first);
    final last = _value(analyses.last);
    final delta = last - first;
    final improving = _metric == _Metric.fillerRate ? delta < 0 : delta > 0;
    return Card(
      color: improving ? const Color(0xFFEAF3F1) : const Color(0xFFFDF1EE),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(improving ? Icons.trending_up : Icons.trending_down,
                color: improving
                    ? const Color(0xFF2E7D5B)
                    : const Color(0xFFB44A3F)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${_metricLabel()} went from ${first.toStringAsFixed(1)} to '
                '${last.toStringAsFixed(1)} across your sessions.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
