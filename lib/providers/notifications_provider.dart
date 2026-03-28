import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/in_app_notification.dart';

const _prefsKey = 'in_app_notifications_v1';
const _maxItems = 80;

class NotificationsProvider extends ChangeNotifier {
  final List<InAppNotification> _items = [];
  int _unreadCount = 0;

  List<InAppNotification> get items => List.unmodifiable(_items);

  int get unreadCount => _unreadCount;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    _items.clear();
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        for (final e in list) {
          if (e is Map) {
            _items.add(
              InAppNotification.fromJson(Map<String, dynamic>.from(e)),
            );
          }
        }
      } catch (_) {}
    }
    _unreadCount = 0;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_items.map((e) => e.toJson()).toList());
    await prefs.setString(_prefsKey, encoded);
  }

  Future<void> add({required String title, required String body}) async {
    final n = InAppNotification(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      body: body,
      createdAt: DateTime.now(),
    );
    _items.insert(0, n);
    while (_items.length > _maxItems) {
      _items.removeLast();
    }
    _unreadCount += 1;
    notifyListeners();
    await _persist();
  }

  void markAllSeen() {
    if (_unreadCount == 0) return;
    _unreadCount = 0;
    notifyListeners();
  }

  Future<void> clearAll() async {
    _items.clear();
    _unreadCount = 0;
    notifyListeners();
    await _persist();
  }
}
