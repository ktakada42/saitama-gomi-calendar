import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:saitama_gomi/app.dart';
import 'package:saitama_gomi/data/area_catalog.dart';
import 'package:saitama_gomi/data/waste_dictionary.dart';
import 'package:saitama_gomi/domain/collection_boxes.dart';
import 'package:saitama_gomi/domain/not_accepted_guide.dart';
import 'package:saitama_gomi/domain/oversized_guide.dart';
import 'package:saitama_gomi/data/notification_repository.dart';
import 'package:saitama_gomi/data/widget_bridge.dart';
import 'package:saitama_gomi/domain/collection_area.dart';
import 'package:saitama_gomi/domain/collection_calendar.dart';
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

/// 5区分すべてが同じ日に重なる地区。1日の内容が最も多くなる場合を試す。
const manyCategoryArea = CollectionArea(
  id: CollectionArea.customAreaId,
  ward: '浦和区',
  name: 'テスト地区',
  rules: {
    GarbageCategory.burnable: [CollectionRule.weekly(DateTime.tuesday)],
    GarbageCategory.nonBurnable: [CollectionRule.weekly(DateTime.tuesday)],
    GarbageCategory.hazardous: [CollectionRule.weekly(DateTime.tuesday)],
    GarbageCategory.recyclable1: [CollectionRule.weekly(DateTime.tuesday)],
    GarbageCategory.recyclable2: [CollectionRule.weekly(DateTime.tuesday)],
  },
);

/// テストで使う既定の時刻。正午にしてあるので、出す期限（朝5:30／8:30）は
/// 過ぎている。つまり既定では「明日」が大きく出る。期限前の表示を試すときは
/// pumpApp の now に朝の時刻を渡す。
final testNow = testToday.add(const Duration(hours: 12));

/// 2026年8月6日（木）。もえるごみの日で、翌日は収集なし。
final testToday = DateTime(2026, 8, 6);

/// 分別早見表のテスト用データ。
/// 5区分に入るものと、入らないもの（粗大ごみ）の両方を持たせてある。
/// 粗大ごみの案内は、同梱している本物を読む。
///
/// 画面に出るのは実際に払う金額なので、作り物に置き換えると
/// 「値が正しく出ているか」を確かめたことにならない。
final testCollectionBoxes = CollectionBoxes.fromJson(
  jsonDecode(File('assets/data/collection_boxes.json').readAsStringSync())
      as Map<String, dynamic>,
);

final testNotAcceptedGuide = NotAcceptedGuide.fromJson(
  jsonDecode(File('assets/data/not_accepted.json').readAsStringSync())
      as Map<String, dynamic>,
);

final testOversizedGuide = OversizedGuide.fromJson(
  jsonDecode(File('assets/data/oversized.json').readAsStringSync())
      as Map<String, dynamic>,
);

final testDictionary = WasteDictionary.fromJson({
  'source': 'テスト用の分別早見表',
  'sourceUrl': 'https://example.com/dictionary',
  'items': [
    {
      'name': 'ペットボトル',
      'kanaHead': 'へ',
      'category': 'recyclable1',
      'categoryLabel': '資源物1類',
      'note': '中をすすいで',
    },
    {
      'name': 'カーペット',
      'kanaHead': 'か',
      'category': 'burnable',
      'categoryLabel': 'もえるごみ',
      'note': '',
    },
    {
      'name': 'たんす',
      'kanaHead': 'た',
      'category': 'oversized',
      'categoryLabel': '粗大ごみ・適正処理困難物',
      'note': '直接持込みまたは戸別収集',
    },
  ],
});

final testCatalog = AreaCatalog.fromJson({
  'source': 'テスト用の出典',
  'sourceUrl': 'https://example.com/test',
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
  // 郵便番号検索のテスト用に、1件に絞れるケース・複数候補が残るケースの両方を仕込む。
  'areas': [
    {
      'id': 'test-area-single',
      'ward': '見沼区',
      'name': 'テスト町一丁目',
      'rules': {
        'burnable': [
          {'weekday': 2},
          {'weekday': 5},
        ],
      },
    },
    {
      'id': 'test-area-multi-a',
      'ward': '大宮区',
      'name': 'テスト町二丁目東側',
      'rules': {
        'burnable': [
          {'weekday': 1},
          {'weekday': 4},
        ],
      },
    },
    {
      'id': 'test-area-multi-b',
      'ward': '大宮区',
      'name': 'テスト町二丁目西側',
      'earlyMorning': true,
      'rules': {
        'burnable': [
          {'weekday': 3},
          {'weekday': 6},
        ],
      },
    },
  ],
  'postalAreas': {
    // 1件に絞れる。
    '3300001': ['test-area-single'],
    // 複数候補が残る。
    '3300002': ['test-area-multi-a', 'test-area-multi-b'],
    // 3300099 はどの地区にも対応しない（該当なしのテスト用に意図的に未登録）。
  },
});

/// 「このアプリについて」に出すバージョン。実機のパッケージ情報は
/// テスト環境では読めないので、決め打ちの値を渡す。
final testPackageInfo = PackageInfo(
  appName: 'saitama_gomi',
  packageName: 'io.github.ktakada42.saitamagomicalendar',
  version: '1.2.3',
  buildNumber: '45',
);

/// テストで使う画面サイズ。
///
/// テストの既定ビューポート（800x600）は横長で、縦画面前提のこのアプリとは
/// 縦横比が逆になるため、実機に近い縦長を使う。
enum TestViewport {
  /// ふだんのテスト用。近年のiPhoneに近い縦長。
  standard(Size(400, 900)),

  /// サポートする下限の画面（iPhone SE 第2/第3世代、375×667pt）。
  /// 現行機種でいちばん小さいので、ここで溢れなければ他では溢れない。
  compact(Size(375, 667));

  const TestViewport(this.size);

  final Size size;
}

void _useViewport(WidgetTester tester, TestViewport viewport) {
  tester.view.physicalSize = viewport.size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// 初回設定からの遷移を確かめるため、アプリ全体（[SaitamaGomiApp]）を立ち上げる。
Future<void> pumpRootApp(
  WidgetTester tester, {
  CollectionArea? area = sampleArea,
  DateTime? today,

  /// 時刻まで含めた「今」。省略すると [today] の正午（＝出す期限を過ぎた状態）。
  DateTime? now,

  /// 同梱データの読み込みが失敗した場合の表示を確かめるためのスイッチ。
  bool failCatalog = false,

  /// 画面サイズ。下限の端末で溢れないかを見るときは [TestViewport.compact]。
  TestViewport viewport = TestViewport.standard,
}) async {
  _useViewport(tester, viewport);
  SharedPreferences.setMockInitialValues({
    if (area != null) 'flutter.selected_area': jsonEncode(area.toJson()),
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        nowProvider.overrideWithValue(
          now ?? (today ?? testToday).add(const Duration(hours: 12)),
        ),
        todayProvider.overrideWithValue(
          CollectionCalendar.dateOnly(
            now ?? (today ?? testToday).add(const Duration(hours: 12)),
          ),
        ),
        areaCatalogProvider.overrideWith(
          (ref) async => failCatalog ? throw Exception('読み込み失敗') : testCatalog,
        ),
        // OSの通知プラグインはテスト環境では初期化できないので差し替える。
        notificationRepositoryProvider.overrideWith(
          (ref) async => const NoopNotificationRepository(),
        ),
        // ウィジェットへの書き出しはプラットフォームチャネル越しなので動かない。
        widgetBridgeProvider.overrideWithValue(const NoopWidgetBridge()),
        wasteDictionaryProvider.overrideWith((ref) async => testDictionary),
        oversizedGuideProvider.overrideWith((ref) async => testOversizedGuide),
        notAcceptedGuideProvider.overrideWith(
          (ref) async => testNotAcceptedGuide,
        ),
        collectionBoxesProvider.overrideWith(
          (ref) async => testCollectionBoxes,
        ),
        packageInfoProvider.overrideWith((ref) async => testPackageInfo),
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

  /// 時刻まで含めた「今」。省略すると [today] の正午（＝出す期限を過ぎた状態）。
  DateTime? now,

  /// 分別早見表。索引の見え方など、品目の並びが要るテストから差し替える。
  WasteDictionary? dictionary,

  /// 画面サイズ。下限の端末で溢れないかを見るときは [TestViewport.compact]。
  TestViewport viewport = TestViewport.standard,
}) async {
  _useViewport(tester, viewport);
  SharedPreferences.setMockInitialValues({
    if (area != null) 'flutter.selected_area': jsonEncode(area.toJson()),
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        nowProvider.overrideWithValue(
          now ?? (today ?? testToday).add(const Duration(hours: 12)),
        ),
        todayProvider.overrideWithValue(
          CollectionCalendar.dateOnly(
            now ?? (today ?? testToday).add(const Duration(hours: 12)),
          ),
        ),
        areaCatalogProvider.overrideWith((ref) async => testCatalog),
        oversizedGuideProvider.overrideWith((ref) async => testOversizedGuide),
        notAcceptedGuideProvider.overrideWith(
          (ref) async => testNotAcceptedGuide,
        ),
        collectionBoxesProvider.overrideWith(
          (ref) async => testCollectionBoxes,
        ),
        // OSの通知プラグインはテスト環境では初期化できないので差し替える。
        notificationRepositoryProvider.overrideWith(
          (ref) async => const NoopNotificationRepository(),
        ),
        // ウィジェットへの書き出しはプラットフォームチャネル越しなので動かない。
        widgetBridgeProvider.overrideWithValue(const NoopWidgetBridge()),
        wasteDictionaryProvider.overrideWith(
          (ref) async => dictionary ?? testDictionary,
        ),
        packageInfoProvider.overrideWith((ref) async => testPackageInfo),
      ],
      child: MaterialApp(
        // 色の見え方を確かめるテストがあるので、実際のテーマを当てる。
        theme: SaitamaGomiApp.themeOf(Brightness.light),
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
