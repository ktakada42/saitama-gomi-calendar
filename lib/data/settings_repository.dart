import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/collection_area.dart';

/// 利用者が設定した地区の保存先。
///
/// 地区はプリセットを選んだあと曜日を調整できるので、IDだけでは復元できない。
/// そのため地区オブジェクトをまるごとJSONで持つ。保存するのはこれ1件だけで、
/// 個人を特定する情報は含まれない。
class SettingsRepository {
  const SettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _areaKey = 'selected_area';

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
}
