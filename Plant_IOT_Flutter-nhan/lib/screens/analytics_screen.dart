import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/server_defaults.dart';
import '../providers/analytics_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/network_error_message.dart';
import '../widgets/app_card.dart';
import '../widgets/section_label.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final analytics = context.watch<AnalyticsProvider>();

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
            const Expanded(child: _AnalyticsBody()),
          ],
        ),
      ),
    );
  }
}

class _AnalyticsBody extends StatefulWidget {
  const _AnalyticsBody();

  @override
  State<_AnalyticsBody> createState() => _AnalyticsBodyState();
}

class _AnalyticsBodyState extends State<_AnalyticsBody> {
  int _retryToken = 0;

  void _retry() => setState(() => _retryToken += 1);

  String _serverUrl(SettingsProvider settings) {
    final saved = settings.serverUrl.trim();
    return saved.isNotEmpty ? saved : kDefaultIotServerUrl;
  }

  @override
  Widget build(BuildContext context) {
    final analytics = context.watch<AnalyticsProvider>();
    final settings = context.watch<SettingsProvider>();
    final scheme = Theme.of(context).colorScheme;
    final serverUrl = _serverUrl(settings);

    return FutureBuilder<ChartSeries>(
      key: ValueKey('${analytics.range}-$_retryToken'),
      future: analytics.loadSeries(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _AnalyticsErrorState(
            message: friendlyNetworkError(
              snap.error!,
              serverUrl: serverUrl,
            ),
            serverUrl: serverUrl,
            onRetry: _retry,
          );
        }
        final data = snap.data!;
        if (!data.hasAnyData) {
          return _AnalyticsEmptyState(
            hourly: data.range.isHourly,
            onRetry: _retry,
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            setState(() => _retryToken += 1);
            await analytics.loadSeries();
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
            const SectionLabel('Nhiệt độ (°C)'),
            AppCard(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
              child: SizedBox(
                height: 200,
                child: _MetricLineChart(
                  spots: data.temperature,
                  labels: data.sensorLabels,
                  color: scheme.primary,
                  unit: '°C',
                  fallbackMin: 20,
                  fallbackMax: 40,
                ),
              ),
            ),
            const SizedBox(height: 18),
            const SectionLabel('Độ ẩm (%)'),
            AppCard(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
              child: SizedBox(
                height: 200,
                child: _MetricLineChart(
                  spots: data.humidity,
                  labels: data.sensorLabels,
                  color: scheme.tertiary,
                  unit: '%',
                  fallbackMin: 60,
                  fallbackMax: 100,
                ),
              ),
            ),
            const SizedBox(height: 22),
            const SectionLabel('Lần chạy máy bơm'),
            AppCard(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
              child: SizedBox(
                height: 210,
                child: data.pumpCounts.isEmpty
                    ? const _ChartPlaceholder(
                        message: 'Chưa có lần bơm trong khoảng thời gian này',
                      )
                    : _PumpBarChart(
                        counts: data.pumpCounts,
                        labels: data.pumpLabels,
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
          ),
        );
      },
    );
  }
}

class _AnalyticsEmptyState extends StatelessWidget {
  const _AnalyticsEmptyState({
    required this.hourly,
    required this.onRetry,
  });

  final bool hourly;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rangeLabel = hourly ? '24 giờ qua' : 'khoảng thời gian đã chọn';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: AppCard(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.insights_outlined,
                size: 36,
                color: scheme.onSurface.withValues(alpha: 0.35),
              ),
              const SizedBox(height: 14),
              Text(
                'Chưa có dữ liệu hoạt động',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Chỉ hiển thị khi có cảm biến gửi mẫu hoặc máy bơm chạy trong $rangeLabel.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.72),
                      height: 1.45,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text('Tải lại'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChartPlaceholder extends StatelessWidget {
  const _ChartPlaceholder({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.45),
            ),
      ),
    );
  }
}

class _AnalyticsErrorState extends StatelessWidget {
  const _AnalyticsErrorState({
    required this.message,
    required this.serverUrl,
    required this.onRetry,
  });

  final String message;
  final String serverUrl;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: AppCard(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 36,
                color: scheme.error.withValues(alpha: 0.85),
              ),
              const SizedBox(height: 14),
              Text(
                'Không tải được biểu đồ',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.72),
                      height: 1.45,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'Server hiện tại: $serverUrl',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.5),
                      fontWeight: FontWeight.w600,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricLineChart extends StatelessWidget {
  const _MetricLineChart({
    required this.spots,
    required this.labels,
    required this.color,
    required this.unit,
    required this.fallbackMin,
    required this.fallbackMax,
  });

  final List<FlSpot> spots;
  final List<String> labels;
  final Color color;
  final String unit;
  final double fallbackMin;
  final double fallbackMax;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (spots.isEmpty) {
      return Center(
        child: Text(
          'Chưa có dữ liệu',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.45),
              ),
        ),
      );
    }

    final values = spots.map((s) => s.y);
    final dataMin = values.reduce((a, b) => a < b ? a : b);
    final dataMax = values.reduce((a, b) => a > b ? a : b);
    final span = (dataMax - dataMin).abs();
    final pad = span < 0.5 ? 2.0 : (span * 0.12).clamp(1.0, 8.0);
    final minY = (dataMin - pad).clamp(fallbackMin, fallbackMax - 1);
    final maxY = (dataMax + pad).clamp(fallbackMin + 1, fallbackMax);
    final yInterval = ((maxY - minY) / 4).clamp(0.5, 50.0);

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: labels.isEmpty ? 0 : (labels.length - 1).toDouble(),
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yInterval,
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
              reservedSize: 36,
              interval: yInterval,
              getTitlesWidget: (v, m) => Text(
                v.toStringAsFixed(span < 2 ? 1 : 0),
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
              reservedSize: labels.length > 10 ? 30 : 22,
              interval: _labelInterval(labels.length),
              getTitlesWidget: (v, m) =>
                  _bottomLabel(context, labels, v.round()),
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: scheme.outline.withValues(alpha: 0.32)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.22,
            barWidth: 2.8,
            color: color,
            dotData: FlDotData(
              show: labels.length <= 14,
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: 3,
                color: color,
                strokeWidth: 1.5,
                strokeColor: scheme.surface,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.08),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touched) => touched.map((bar) {
              final y = bar.y;
              return LineTooltipItem(
                '${y.toStringAsFixed(1)} $unit',
                TextStyle(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

Widget _bottomLabel(BuildContext context, List<String> labels, int index) {
  if (index < 0 || index >= labels.length) {
    return const SizedBox.shrink();
  }
  final scheme = Theme.of(context).colorScheme;
  final text = Text(
    labels[index],
    style: TextStyle(
      fontSize: 10,
      color: scheme.onSurface.withValues(alpha: 0.4),
    ),
  );
  if (labels.length <= 10) return text;
  return Transform.rotate(angle: -0.45, child: text);
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
              getTitlesWidget: (v, m) =>
                  _bottomLabel(context, labels, v.round()),
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
