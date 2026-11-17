import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/app.dart';
import 'package:saitama_gomi/data/waste_dictionary.dart';
import 'package:saitama_gomi/features/calendar/calendar_page.dart';
import 'package:saitama_gomi/features/dictionary/dictionary_page.dart';
import 'package:saitama_gomi/features/home/home_page.dart';
import 'package:saitama_gomi/features/settings/settings_page.dart';
import 'package:saitama_gomi/ui/liquid_glass/liquid_glass_surface.dart';

import '../support/test_app.dart';

/// 地とその上に重なる面が緑がからないことを確かめる。
///
/// `ColorScheme.fromSeed`は中間色もシード色（緑）の色相へ寄せる。
/// これまで薄緑が出るたびに、その色（surface、primaryContainer、
/// secondaryContainer、surfaceContainer…）を1つずつ潰してきたが、
/// 潰し漏れが残るたびに同じ指摘を受けた。役割ごとではなく、
/// 面に使われる色を総なめにして検査する。
void main() {
  // 実際に画面へ出るシートでも確かめる。M3のシートは背景に
  // surfaceContainerLowを使うので、そこが緑のままだと
  // 外観やお知らせの時刻を開いたときに薄緑に見える。
  testWidgets('シートの背景も緑に寄っていない', (tester) async {
    await pumpApp(tester, const SettingsPage());
    await tester.tap(find.text('外観'));
    await tester.pumpAndSettle();

    final material = tester
        .widgetList<Material>(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Material),
          ),
        )
        .first;
    final argb = material.color!.toARGB32();
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    expect(
      g,
      lessThanOrEqualTo(r),
      reason:
          'シートの背景 (#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}) が薄緑に見える',
    );
  });

  testWidgets('Liquid Glass の全シート・ダイアログも tintColor 無しで緑に寄らない', (tester) async {
    void expectUntintedGlass(Finder scope, String label) {
      final surface = tester
          .widgetList<LiquidGlassSurface>(
            find.descendant(
              of: scope,
              matching: find.byType(LiquidGlassSurface),
            ),
          )
          .first;
      expect(
        surface.tintColor,
        isNull,
        reason: '$label に tintColor が渡っており UIGlassEffect で色転びする',
      );
    }

    // 1. ホームの日付詳細シート
    await pumpApp(tester, const HomePage(), liquidGlass: true);
    await tester.tap(find.textContaining('もえるごみ').first);
    await tester.pumpAndSettle();
    expectUntintedGlass(find.byType(BottomSheet), 'ホームの日付詳細シート');
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // 2. カレンダーの日付詳細シート（2026年8月10日＝月曜・もえるごみの日）
    await pumpApp(tester, const CalendarPage(), liquidGlass: true);
    await tester.tap(find.text('10'));
    await tester.pumpAndSettle();
    expectUntintedGlass(find.byType(BottomSheet), 'カレンダーの日付詳細シート');
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // 3. 分別の品目詳細シート & 5. 出典ダイアログ
    await pumpApp(
      tester,
      const DictionaryPage(),
      liquidGlass: true,
      dictionary: WasteDictionary.fromJson(
        {
          'source': 'テスト用の分別資料',
          'sourceUrl': 'https://example.com/dict',
          'items': [
            {
              'name': 'たんす',
              'kanaHead': 'た',
              'category': 'oversized',
              'categoryLabel': '粗大ごみ・適正処理困難物',
              'note': '最大の辺または径が90センチメートル以上のもの',
              'marks': ['star2'],
            },
          ],
        },
        changes: const {'source': 'テスト用', 'sourceUrl': 'https://example.com'},
      ),
    );
    await tester.tap(find.text('たんす'));
    await tester.pumpAndSettle();
    expectUntintedGlass(find.byType(BottomSheet), '分別の品目詳細シート');
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('出典'));
    await tester.pumpAndSettle();
    final dialogGlass = tester
        .widgetList<LiquidGlassSurface>(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.byType(LiquidGlassSurface),
          ),
        )
        .first;
    expect(dialogGlass.tintColor, isNull, reason: '出典ダイアログに tintColor が渡っている');
    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();

    // 4. 設定のお知らせ時刻シート & 外観シート
    await pumpApp(tester, const SettingsPage(), liquidGlass: true);
    await tester.tap(find.widgetWithText(SwitchListTile, '通知'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('お知らせの時刻'));
    await tester.pumpAndSettle();
    expectUntintedGlass(find.byType(BottomSheet), 'お知らせの時刻シート');
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('外観'));
    await tester.pumpAndSettle();
    expectUntintedGlass(find.byType(BottomSheet), '外観シート');
  });

  testWidgets('検索履歴チップの背景も緑に寄っていない', (tester) async {
    await pumpApp(
      tester,
      const DictionaryPage(),
      preferences: {
        'flutter.dictionary_search_history': <String>['ペットボトル'],
      },
    );

    final chip = tester.widget<InputChip>(find.byType(InputChip));
    final argb = chip.backgroundColor!.toARGB32();
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    expect(
      g,
      lessThanOrEqualTo(r),
      reason:
          '検索履歴チップの背景 (#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}) が薄緑に見える',
    );
  });

  for (final brightness in Brightness.values) {
    final scheme = SaitamaGomiApp.themeOf(brightness).colorScheme;
    final surfaces = {
      'surface': scheme.surface,
      'surfaceContainerLowest': scheme.surfaceContainerLowest,
      'surfaceContainerLow': scheme.surfaceContainerLow,
      'surfaceContainer': scheme.surfaceContainer,
      'surfaceContainerHigh': scheme.surfaceContainerHigh,
      'surfaceContainerHighest': scheme.surfaceContainerHighest,
      'surfaceBright': scheme.surfaceBright,
      'surfaceDim': scheme.surfaceDim,
      'primaryContainer': scheme.primaryContainer,
      'secondaryContainer': scheme.secondaryContainer,
    };

    group('$brightness の面の色', () {
      surfaces.forEach((name, color) {
        test('$name は緑に寄っていない', () {
          final r = (color.toARGB32() >> 16) & 0xFF;
          final g = (color.toARGB32() >> 8) & 0xFF;
          final b = color.toARGB32() & 0xFF;
          // クリームは赤≧緑≧青。緑がかると緑が赤を追い越す。
          expect(
            g,
            lessThanOrEqualTo(r),
            reason:
                '$name (#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}) '
                'は緑が赤を上回っており、薄緑に見える',
          );
          expect(b, lessThanOrEqualTo(g), reason: '$name が青に寄っている');
        });
      });
    });
  }
}
