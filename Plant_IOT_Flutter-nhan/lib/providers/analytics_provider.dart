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

    final buckets = <AnalyticsBucket>[];
    final temp = <FlSpot>[];
    final humidity = <FlSpot>[];
    final pumpBars = <int>[];

    for (var i = 0; i < rows.length; i += 1) {
      final raw = rows[i];
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      final bucket = AnalyticsBucket(
        label: row['label']?.toString() ?? i.toString(),
        avgTemperature: _toDouble(row['avg_temperature']),
        avgHumidity: _toDouble(row['avg_humidity']),
        pumpCount: _toInt(row['pump_count']),
        sampleCount: _toInt(row['sample_count']),
      );
      buckets.add(bucket);
      final x = (buckets.length - 1).toDouble();
      if (bucket.avgTemperature != null) {
        temp.add(FlSpot(x, bucket.avgTemperature!));
      }
      if (bucket.avgHumidity != null) {
        humidity.add(FlSpot(x, bucket.avgHumidity!));
      }
      pumpBars.add(bucket.pumpCount);
    }

    return ChartSeries(
      range: range,
      temperature: temp,
      humidity: humidity,
      pumpCounts: pumpBars,
      buckets: buckets,
    );
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
    required this.pumpCounts,
    required this.buckets,
  });

  final AnalyticsRange range;
  final List<FlSpot> temperature;
  final List<FlSpot> humidity;
  final List<int> pumpCounts;
  final List<AnalyticsBucket> buckets;
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
