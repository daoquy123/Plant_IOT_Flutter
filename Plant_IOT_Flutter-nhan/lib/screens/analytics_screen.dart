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
                  final labels = data.buckets.map((b) => b.label).toList();
                  return ListView(
                    children: [
                      const SectionLabel('Nhiệt độ & độ ẩm'),
                      AppCard(
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              height: 210,
                              child: _LineDualChart(
                                temp: data.temperature,
                                humidity: data.humidity,
                                labels: labels,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _LegendLine(
                              label: 'Nhiệt độ (°C)',
                              color: scheme.primary,
                            ),
                            const SizedBox(height: 6),
                            _LegendLine(
                              label: 'Độ ẩm (%)',
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
                          child: _PumpBarChart(
                            counts: data.pumpCounts,
                            labels: labels,
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      SectionLabel(
                        data.range.isHourly
                            ? 'Thông số theo giờ'
                            : 'Trung bình theo ngày',
                      ),
                      AppCard(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        child: _BucketSummaryTable(
                          buckets: data.buckets,
                          hourly: data.range.isHourly,
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
        Container(width: 18, height: 2, color: color),
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
    required this.humidity,
    required this.labels,
  });

  final List<FlSpot> temp;
  final List<FlSpot> humidity;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: labels.isEmpty ? 0 : (labels.length - 1).toDouble(),
        minY: 0,
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
              interval: _labelInterval(labels.length),
              getTitlesWidget: (v, m) {
                final index = v.round();
                if (index < 0 || index >= labels.length) {
                  return const SizedBox.shrink();
                }
                return Text(
                  labels[index],
                  style: TextStyle(
                    fontSize: 10,
                    color: scheme.onSurface.withValues(alpha: 0.4),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: scheme.outline.withValues(alpha: 0.32)),
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
            spots: humidity,
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
  const _PumpBarChart({required this.counts, required this.labels});

  final List<int> counts;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxCount =
        counts.isEmpty ? 1 : counts.reduce((a, b) => a > b ? a : b);
    return BarChart(
      BarChartData(
        maxY: (maxCount + 1).toDouble(),
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
              interval: _labelInterval(labels.length),
              getTitlesWidget: (v, m) {
                final index = v.round();
                if (index < 0 || index >= labels.length) {
                  return const SizedBox.shrink();
                }
                return Text(
                  labels[index],
                  style: TextStyle(
                    fontSize: 10,
                    color: scheme.onSurface.withValues(alpha: 0.4),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: scheme.outline.withValues(alpha: 0.45)),
        ),
        barGroups: List.generate(
          counts.length,
          (i) => BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: counts[i].toDouble(),
                width: counts.length > 20 ? 6 : 11,
                color: scheme.primary.withValues(alpha: 0.88),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(6)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BucketSummaryTable extends StatelessWidget {
  const _BucketSummaryTable({required this.buckets, required this.hourly});

  final List<AnalyticsBucket> buckets;
  final bool hourly;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final headerStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface.withValues(alpha: 0.62),
        );
    final cellStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onSurface.withValues(alpha: 0.74),
        );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 34,
        dataRowMinHeight: 34,
        dataRowMaxHeight: 38,
        columnSpacing: 18,
        horizontalMargin: 0,
        columns: [
          DataColumn(label: Text(hourly ? 'Giờ' : 'Ngày', style: headerStyle)),
          DataColumn(label: Text('Nhiệt độ', style: headerStyle)),
          DataColumn(label: Text('Độ ẩm', style: headerStyle)),
          DataColumn(label: Text('Số lần bơm', style: headerStyle)),
        ],
        rows: buckets
            .map(
              (bucket) => DataRow(
                cells: [
                  DataCell(Text(bucket.label, style: cellStyle)),
                  DataCell(Text(
                    _formatValue(bucket.avgTemperature, '°C'),
                    style: cellStyle,
                  )),
                  DataCell(Text(
                    _formatValue(bucket.avgHumidity, '%'),
                    style: cellStyle,
                  )),
                  DataCell(Text(bucket.pumpCount.toString(), style: cellStyle)),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  String _formatValue(double? value, String unit) {
    if (value == null) return '-';
    return '${value.toStringAsFixed(1)} $unit';
  }
}

double _labelInterval(int length) {
  if (length > 20) return 5;
  if (length > 10) return 3;
  return 1;
}
