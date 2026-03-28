import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/analytics_provider.dart';
import '../widgets/app_card.dart';
import '../widgets/section_label.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final analytics = context.watch<AnalyticsProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Phân tích')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<AnalyticsRange>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: AnalyticsRange.oneDay,
                  label: Text('1D'),
                ),
                ButtonSegment(
                  value: AnalyticsRange.sevenDays,
                  label: Text('7D'),
                ),
                ButtonSegment(
                  value: AnalyticsRange.thirtyDays,
                  label: Text('30D'),
                ),
              ],
              selected: {analytics.range},
              onSelectionChanged: (s) {
                if (s.isEmpty) return;
                context.read<AnalyticsProvider>().setRange(s.first);
              },
            ),
            const SizedBox(height: 20),
            Expanded(
              child: FutureBuilder<ChartSeries>(
                key: ValueKey(analytics.range),
                future: analytics.loadSeries(),
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(
                      child: Text(
                        snap.error.toString(),
                        style: TextStyle(color: scheme.error, fontSize: 13),
                      ),
                    );
                  }
                  final data = snap.data!;
                  return ListView(
                    children: [
                      const SectionLabel('Nhiệt độ & ẩm đất'),
                      AppCard(
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              height: 210,
                              child: _LineDualChart(
                                temp: data.temperature,
                                moisture: data.soilMoisture,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _LegendLine(
                              label: 'Nhiệt độ (°C)',
                              color: scheme.primary,
                            ),
                            const SizedBox(height: 6),
                            _LegendLine(
                              label: 'Ẩm đất (%)',
                              color: scheme.onSurface.withValues(alpha: 0.38),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      const SectionLabel('Lần chạy máy bơm'),
                      AppCard(
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
                        child: SizedBox(
                          height: 210,
                          child: _PumpBarChart(counts: data.pumpCounts),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendLine extends StatelessWidget {
  const _LegendLine({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 18,
          height: 2,
          color: color,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.55),
              ),
        ),
      ],
    );
  }
}

class _LineDualChart extends StatelessWidget {
  const _LineDualChart({
    required this.temp,
    required this.moisture,
  });

  final List<FlSpot> temp;
  final List<FlSpot> moisture;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 10,
          getDrawingHorizontalLine: (v) => FlLine(
            color: scheme.outline.withValues(alpha: 0.35),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval: 20,
              getTitlesWidget: (v, m) => Text(
                v.toInt().toString(),
                style: TextStyle(
                  fontSize: 10,
                  color: scheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 1,
              getTitlesWidget: (v, m) => Text(
                v.toInt().toString(),
                style: TextStyle(
                  fontSize: 10,
                  color: scheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(
            color: scheme.outline.withValues(alpha: 0.32),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: temp,
            isCurved: true,
            curveSmoothness: 0.22,
            barWidth: 2.6,
            color: scheme.primary,
            dotData: const FlDotData(show: false),
          ),
          LineChartBarData(
            spots: moisture,
            isCurved: true,
            curveSmoothness: 0.22,
            barWidth: 2.6,
            color: scheme.onSurface.withValues(alpha: 0.38),
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}

class _PumpBarChart extends StatelessWidget {
  const _PumpBarChart({required this.counts});

  final List<int> counts;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return BarChart(
      BarChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 1,
          getDrawingHorizontalLine: (v) => FlLine(
            color: scheme.outline.withValues(alpha: 0.35),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 1,
              getTitlesWidget: (v, m) => Text(
                v.toInt().toString(),
                style: TextStyle(
                  fontSize: 10,
                  color: scheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (v, m) => Text(
                v.toInt().toString(),
                style: TextStyle(
                  fontSize: 10,
                  color: scheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(
            color: scheme.outline.withValues(alpha: 0.45),
          ),
        ),
        barGroups: List.generate(
          counts.length,
          (i) => BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: counts[i].toDouble(),
                width: 11,
                color: scheme.primary.withValues(alpha: 0.88),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
