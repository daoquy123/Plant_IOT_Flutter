import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

enum AnalyticsRange { oneDay, sevenDays, thirtyDays }

extension on AnalyticsRange {
  int get days => switch (this) {
        AnalyticsRange.oneDay => 1,
        AnalyticsRange.sevenDays => 7,
        AnalyticsRange.thirtyDays => 30,
      };
}

class AnalyticsProvider extends ChangeNotifier {
  AnalyticsRange range = AnalyticsRange.sevenDays;

  void setRange(AnalyticsRange r) {
    if (range == r) return;
    range = r;
    notifyListeners();
  }

  /// Dữ liệu demo — thay bằng HTTP lấy lịch sử từ server / ESP.
  Future<ChartSeries> loadSeries() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final days = range.days;
    final rnd = Random(42);
    final temp = <FlSpot>[];
    final moisture = <FlSpot>[];
    for (var i = 0; i < days; i++) {
      final x = i.toDouble();
      temp.add(FlSpot(x, 24 + rnd.nextDouble() * 6));
      moisture.add(FlSpot(x, 45 + rnd.nextDouble() * 25));
    }
    final pumpBars = <int>[];
    for (var i = 0; i < days; i++) {
      pumpBars.add(rnd.nextInt(5));
    }
    return ChartSeries(
      temperature: temp,
      soilMoisture: moisture,
      pumpCounts: pumpBars,
    );
  }
}

class ChartSeries {
  ChartSeries({
    required this.temperature,
    required this.soilMoisture,
    required this.pumpCounts,
  });

  final List<FlSpot> temperature;
  final List<FlSpot> soilMoisture;
  final List<int> pumpCounts;
}
