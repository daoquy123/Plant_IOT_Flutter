import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../config/server_defaults.dart';
import '../data/esp32_client.dart';
import 'settings_provider.dart';

enum AnalyticsRange { oneDay, sevenDays, thirtyDays }

extension AnalyticsRangeApi on AnalyticsRange {
  String get apiValue => switch (this) {
        AnalyticsRange.oneDay => '1d',
        AnalyticsRange.sevenDays => '7d',
        AnalyticsRange.thirtyDays => '30d',
      };

  bool get isHourly => this == AnalyticsRange.oneDay;
}

class AnalyticsProvider extends ChangeNotifier {
  AnalyticsProvider({Esp32Client? esp32}) : _esp32 = esp32 ?? Esp32Client();

  final Esp32Client _esp32;
  SettingsProvider? _settings;
  AnalyticsRange range = AnalyticsRange.sevenDays;

  void attachSettings(SettingsProvider settings) {
    _settings = settings;
  }

  void setRange(AnalyticsRange r) {
    if (range == r) return;
    range = r;
    notifyListeners();
  }

  Future<ChartSeries> loadSeries() async {
    final serverBase = _settings?.serverUrl.trim().isNotEmpty == true
        ? _settings!.serverUrl.trim()
        : kDefaultIotServerUrl;
    final apiKey = _settings?.apiKey.trim() ?? '';
    if (serverBase.isEmpty || apiKey.isEmpty) {
      throw StateError('Thiếu URL server IoT hoặc API key trong Cài đặt');
    }

    final map = await _esp32.fetchAnalytics(
      serverBase: serverBase,
      apiKey: apiKey,
      range: range.apiValue,
    );
    final rows = map['buckets'];
    if (rows is! List) {
      throw const FormatException('Server không trả dữ liệu biểu đồ hợp lệ');
    }

    final allBuckets = <AnalyticsBucket>[];

    for (var i = 0; i < rows.length; i += 1) {
      final raw = rows[i];
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      allBuckets.add(
        AnalyticsBucket(
          label: row['label']?.toString() ?? i.toString(),
          avgTemperature: _toDouble(row['avg_temperature']),
          avgHumidity: _toDouble(row['avg_humidity']),
          pumpCount: _toInt(row['pump_count']),
          sampleCount: _toInt(row['sample_count']),
        ),
      );
    }

    // Chỉ hiển thị mốc có dữ liệu thật — tránh 24h/30 ngày trống làm chart lỗi.
    final sensorBuckets =
        allBuckets.where((b) => b.sampleCount > 0).toList(growable: false);
    final pumpBuckets =
        allBuckets.where((b) => b.pumpCount > 0).toList(growable: false);
    final tableBuckets = allBuckets
        .where((b) => b.sampleCount > 0 || b.pumpCount > 0)
        .toList(growable: false);

    return ChartSeries(
      range: range,
      temperature: _spotsFrom(sensorBuckets, (b) => b.avgTemperature),
      humidity: _spotsFrom(sensorBuckets, (b) => b.avgHumidity),
      sensorLabels: sensorBuckets.map((b) => b.label).toList(),
      pumpCounts: pumpBuckets.map((b) => b.pumpCount).toList(),
      pumpLabels: pumpBuckets.map((b) => b.label).toList(),
      buckets: tableBuckets,
    );
  }

  static List<FlSpot> _spotsFrom(
    List<AnalyticsBucket> buckets,
    double? Function(AnalyticsBucket b) value,
  ) {
    final spots = <FlSpot>[];
    for (var i = 0; i < buckets.length; i += 1) {
      final y = value(buckets[i]);
      if (y != null) spots.add(FlSpot(i.toDouble(), y));
    }
    return spots;
  }

  static double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static int _toInt(dynamic value) {
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  @override
  void dispose() {
    _esp32.close();
    super.dispose();
  }
}

class ChartSeries {
  ChartSeries({
    required this.range,
    required this.temperature,
    required this.humidity,
    required this.sensorLabels,
    required this.pumpCounts,
    required this.pumpLabels,
    required this.buckets,
  });

  final AnalyticsRange range;
  final List<FlSpot> temperature;
  final List<FlSpot> humidity;
  final List<String> sensorLabels;
  final List<int> pumpCounts;
  final List<String> pumpLabels;
  final List<AnalyticsBucket> buckets;

  bool get hasAnyData => buckets.isNotEmpty;
}

class AnalyticsBucket {
  AnalyticsBucket({
    required this.label,
    required this.avgTemperature,
    required this.avgHumidity,
    required this.pumpCount,
    required this.sampleCount,
  });

  final String label;
  final double? avgTemperature;
  final double? avgHumidity;
  final int pumpCount;
  final int sampleCount;
}
