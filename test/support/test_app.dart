import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/app.dart';
import 'package:saitama_gomi/data/area_catalog.dart';
import 'package:saitama_gomi/domain/collection_area.dart';
import 'package:saitama_gomi/domain/collection_rule.dart';
import 'package:saitama_gomi/domain/garbage_category.dart';
import 'package:saitama_gomi/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// もえるごみ 月・木／資源物1類 水／資源物2類 毎週火／もえないごみ 第2火／
/// 有害危険ごみ 第4火 の地区。ウィジェットテスト共通の題材。
const sampleArea = CollectionArea(
  id: CollectionArea.customAreaId,
  ward: '浦和区',
  name: 'テスト地区',
  rules: {
    GarbageCategory.burnable: [
      CollectionRule.weekly(DateTime.monday),
      CollectionRule.weekly(DateTime.thursday),
    ],
    GarbageCategory.nonBurnable: [
      CollectionRule.monthly(DateTime.tuesday, {2}),
    ],
    GarbageCategory.hazardous: [
      CollectionRule.monthly(DateTime.tuesday, {4}),
    ],
    GarbageCategory.recyclable1: [CollectionRule.weekly(DateTime.wednesday)],
    GarbageCategory.recyclable2: [CollectionRule.weekly(DateTime.tuesday)],
  },
);

/// 2026年8月6日（木）。もえるごみの日で、翌日は収集なし。
final testToday = DateTime(2026, 8, 6);

final testCatalog = AreaCatalog.fromJson({
  'source': 'テスト用の出典',
  'disclaimer': 'テスト用の但し書き',
  'presets': [
    {
      'id': 'preset-mon-thu',
      'ward': '',
      'name': 'もえるごみが月・木の地区',
      'rules': {
        'burnable': [
          {'weekday': 1},
          {'weekday': 4},
        ],
      },
    },
  ],
  'areas': <dynamic>[],
});

/// テストの既定ビューポート（800x600）は横長で、縦画面前提のこのアプリとは
/// 縦横比が逆になる。実機に近い縦長にしておく。
void _useHandsetViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// 初回設定からの遷移を確かめるため、アプリ全体（[SaitamaGomiApp]）を立ち上げる。
Future<void> pumpRootApp(
  WidgetTester tester, {
  CollectionArea? area = sampleArea,
  DateTime? today,
}) async {
  _useHandsetViewport(tester);
  SharedPreferences.setMockInitialValues({
    if (area != null) 'flutter.selected_area': jsonEncode(area.toJson()),
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        todayProvider.overrideWithValue(today ?? testToday),
        areaCatalogProvider.overrideWith((ref) async => testCatalog),
      ],
      child: const SaitamaGomiApp(),
    ),
  );
  await tester.pumpAndSettle();
}

/// 保存済み地区を仕込んだ状態でアプリ画面を立ち上げる。
///
/// `SharedPreferences` のモックを使うので、`SettingsRepository` を含めた
/// 読み書きの経路をそのままテストできる。[area] を省略すると未設定＝初回起動。
Future<void> pumpApp(
  WidgetTester tester,
  Widget child, {
  CollectionArea? area = sampleArea,
  DateTime? today,
}) async {
  _useHandsetViewport(tester);
  SharedPreferences.setMockInitialValues({
    if (area != null) 'flutter.selected_area': jsonEncode(area.toJson()),
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        todayProvider.overrideWithValue(today ?? testToday),
        areaCatalogProvider.overrideWith((ref) async => testCatalog),
      ],
      child: MaterialApp(
        locale: const Locale('ja'),
        supportedLocales: const [Locale('ja')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: child,
      ),
    ),
  );
  // SharedPreferences の読み込みが非同期なので、解決するまで進める。
  await tester.pumpAndSettle();
}
