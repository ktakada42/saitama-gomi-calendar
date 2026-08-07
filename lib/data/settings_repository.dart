import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/collection_area.dart';

/// 収集日前夜の通知の設定。
class NotificationSettings {
  const NotificationSettings({required this.enabled, required this.timeOfDay});

  const NotificationSettings.defaults()
    : enabled = false,
      timeOfDay = const Duration(hours: 20);

  /// 通知を出すかどうか。既定はOFF（利用者が明示的にONにする）。
  final bool enabled;

  /// 収集日の前日の何時に通知するか。既定は20:00。
  final Duration timeOfDay;

  NotificationSettings copyWith({bool? enabled, Duration? timeOfDay}) =>
      NotificationSettings(
        enabled: enabled ?? this.enabled,
        timeOfDay: timeOfDay ?? this.timeOfDay,
      );

  /// 「20:00」のような表示用の文字列。
  String get label {
    final hour = timeOfDay.inHours;
    final minute = timeOfDay.inMinutes % 60;
    return '$hour:${minute.toString().padLeft(2, '0')}';
  }

  @override
  bool operator ==(Object other) =>
      other is NotificationSettings &&
      other.enabled == enabled &&
      other.timeOfDay == timeOfDay;

  @override
  int get hashCode => Object.hash(enabled, timeOfDay);
}

/// 利用者が設定した地区・外観・通知の保存先。
///
/// 地区はプリセットを選んだあと曜日を調整できるので、IDだけでは復元できない。
/// そのため地区オブジェクトをまるごとJSONで持つ。保存するのはこれらの設定だけで、
/// 個人を特定する情報は含まれない。
class SettingsRepository {
  const SettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _areaKey = 'selected_area';
  static const _themeModeKey = 'theme_mode';
  // 地区とは別キーにしてある。地区を選び直しても通知設定は保たれるべきなので。
  static const _notificationEnabledKey = 'notification_enabled';
  static const _notificationMinutesKey = 'notification_minutes';

  static Future<SettingsRepository> open() async =>
      SettingsRepository(await SharedPreferences.getInstance());

  /// 設定済みの地区。未設定（初回起動）なら null。
  CollectionArea? readArea() {
    final raw = _prefs.getString(_areaKey);
    if (raw == null) return null;
    try {
      return CollectionArea.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      // 壊れた保存データで起動できなくなるより、未設定として初回設定に戻す。
      return null;
    }
  }

  Future<void> writeArea(CollectionArea area) =>
      _prefs.setString(_areaKey, jsonEncode(area.toJson()));

  Future<void> clear() => _prefs.remove(_areaKey);

  /// 外観設定。未設定ならライトモード（システムのダークモードには自動追従しない）。
  ThemeMode readThemeMode() {
    final raw = _prefs.getString(_themeModeKey);
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == raw,
      orElse: () => ThemeMode.light,
    );
  }

  Future<void> writeThemeMode(ThemeMode mode) =>
      _prefs.setString(_themeModeKey, mode.name);

  /// 通知設定。未設定なら「OFF・20:00」。
  NotificationSettings readNotificationSettings() {
    const defaults = NotificationSettings.defaults();
    final minutes = _prefs.getInt(_notificationMinutesKey);
    return NotificationSettings(
      enabled: _prefs.getBool(_notificationEnabledKey) ?? defaults.enabled,
      timeOfDay: minutes == null
          ? defaults.timeOfDay
          : Duration(minutes: minutes),
    );
  }

  Future<void> writeNotificationSettings(NotificationSettings settings) async {
    await _prefs.setBool(_notificationEnabledKey, settings.enabled);
    await _prefs.setInt(_notificationMinutesKey, settings.timeOfDay.inMinutes);
  }
}
