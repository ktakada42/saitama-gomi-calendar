import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/data/settings_repository.dart';
import 'package:saitama_gomi/domain/collection_area.dart';
import 'package:saitama_gomi/domain/collection_rule.dart';
import 'package:saitama_gomi/domain/garbage_category.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _area = CollectionArea(
  id: 'test',
  ward: '浦和区',
  name: 'テスト地区',
  rules: {
    GarbageCategory.burnable: [CollectionRule.weekly(DateTime.monday)],
  },
);

Future<SettingsRepository> _openWith(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SettingsRepository.open();
}

void main() {
  group('readArea', () {
    test('未設定なら null', () async {
      final repo = await _openWith({});
      expect(repo.readArea(), isNull);
    });

    test('保存した地区をそのまま読める', () async {
      final repo = await _openWith({
        'flutter.selected_area':
            '{"id":"test","ward":"浦和区","name":"テスト地区",'
            '"earlyMorning":false,'
            '"rules":{"burnable":[{"weekday":1}]}}',
      });
      // CollectionAreaは==を持たないので、値の比較はtoJson()で行う。
      expect(repo.readArea()?.toJson(), _area.toJson());
    });

    // readArea()は「壊れた保存データで起動できなくなるより、未設定として
    // 初回設定に戻す」設計（コード中のコメント参照）。壊れ方には2種類あり、
    // 両方を確かめる。
    group('壊れた保存データからは、クラッシュせず null に復帰する', () {
      test('JSONとして構文が壊れている', () async {
        // 末尾が欠けた文字列。jsonDecode自体がFormatExceptionを投げる。
        final repo = await _openWith({
          'flutter.selected_area': '{"id": "test", "ward": ',
        });
        expect(repo.readArea(), isNull);
      });

      test('JSONの構文は正しいが、期待する形と違う', () async {
        // これらはjsonDecodeまでは成功するので、CollectionArea.fromJson側で
        // TypeErrorになる。FormatExceptionしか捕まえていないと、
        // ここだけ復帰できずに例外が外へ漏れる。
        for (final raw in [
          '{"foo": "bar"}', // idなどのフィールドが無い
          '{"id": 123, "ward": "x", "name": "y"}', // idの型が違う
          'null',
          '"just a string"',
          '[]', // トップレベルがオブジェクトでない
        ]) {
          final repo = await _openWith({'flutter.selected_area': raw});
          expect(repo.readArea(), isNull, reason: raw);
        }
      });
    });
  });

  group('writeArea / clear', () {
    test('書いてすぐ読める', () async {
      final repo = await _openWith({});
      await repo.writeArea(_area);
      expect(repo.readArea()?.toJson(), _area.toJson());
    });

    test('clearすると未設定に戻る', () async {
      final repo = await _openWith({});
      await repo.writeArea(_area);
      await repo.clear();
      expect(repo.readArea(), isNull);
    });
  });

  group('readThemeMode', () {
    test('未設定ならライトモード', () async {
      final repo = await _openWith({});
      expect(repo.readThemeMode(), ThemeMode.light);
    });

    test('壊れた値（存在しないモード名）でもクラッシュせずライトモードに戻る', () async {
      final repo = await _openWith({'flutter.theme_mode': 'sepia'});
      expect(repo.readThemeMode(), ThemeMode.light);
    });

    test('書いた値を読める', () async {
      final repo = await _openWith({});
      await repo.writeThemeMode(ThemeMode.dark);
      expect(repo.readThemeMode(), ThemeMode.dark);
    });
  });

  group('readNotificationSettings', () {
    test('未設定ならOFF・20:00', () async {
      final repo = await _openWith({});
      final settings = repo.readNotificationSettings();
      expect(settings.enabled, isFalse);
      expect(settings.timeOfDay, const Duration(hours: 20));
    });

    test('書いた値を読める', () async {
      final repo = await _openWith({});
      await repo.writeNotificationSettings(
        const NotificationSettings(
          enabled: true,
          timeOfDay: Duration(hours: 7, minutes: 30),
        ),
      );
      final settings = repo.readNotificationSettings();
      expect(settings.enabled, isTrue);
      expect(settings.timeOfDay, const Duration(hours: 7, minutes: 30));
    });

    test('時刻だけ壊れている（enabledは無事）場合も既定の時刻に戻る', () async {
      final repo = await _openWith({
        'flutter.notification_enabled': true,
        // notification_minutesキーが無い状態を模す。
      });
      final settings = repo.readNotificationSettings();
      expect(settings.enabled, isTrue);
      expect(settings.timeOfDay, const Duration(hours: 20));
    });
  });
}
