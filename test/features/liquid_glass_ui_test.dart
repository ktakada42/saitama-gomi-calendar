import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoDatePicker;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saitama_gomi/data/waste_dictionary.dart';
import 'package:saitama_gomi/features/about/about_page.dart';
import 'package:saitama_gomi/features/area/area_editor_page.dart';
import 'package:saitama_gomi/features/area/area_picker_page.dart';
import 'package:saitama_gomi/features/calendar/calendar_page.dart';
import 'package:saitama_gomi/features/dictionary/collection_boxes_page.dart';
import 'package:saitama_gomi/features/dictionary/dictionary_page.dart';
import 'package:saitama_gomi/features/dictionary/not_accepted_guide_page.dart';
import 'package:saitama_gomi/features/dictionary/oversized_guide_page.dart';
import 'package:saitama_gomi/features/home/home_page.dart';
import 'package:saitama_gomi/features/settings/settings_page.dart';
import 'package:saitama_gomi/ui/liquid_glass/liquid_glass_app_bar.dart';
import 'package:saitama_gomi/ui/liquid_glass/liquid_glass_search_bar.dart';
import 'package:saitama_gomi/ui/liquid_glass/liquid_glass_surface.dart';
import 'package:saitama_gomi/ui/liquid_glass/liquid_glass_tab_bar.dart';

import '../support/test_app.dart';

void main() {
  group('Liquid Glass 表示（iOS 26 以降）', () {
    testWidgets('トップ4画面は固定AppBarを持たず、タブバー左右の余白で縦スクロールできる', (tester) async {
      await pumpRootApp(tester, liquidGlass: true);

      expect(find.byType(LiquidGlassTabBar), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(HomePage), findsOneWidget);
      // トップ4画面には上部 AppBar を置かず、地区名はホーム本文の先頭に出す。
      expect(find.byType(AppBar), findsNothing);
      expect(find.textContaining('浦和区 テスト地区'), findsWidgets);

      // タブバーの左右余白（x=8 および右端近く）から縦ドラッグしたとき、
      // タブバーに遮られず背面の ListView がスクロールできることを検証する。
      final homeScrollable = find.descendant(
        of: find.byType(HomePage),
        matching: find.byType(Scrollable),
      );
      final beforeLeftDrag = tester
          .state<ScrollableState>(homeScrollable)
          .position
          .pixels;
      final tabRect = tester.getRect(find.byType(LiquidGlassTabBar));
      await tester.dragFrom(
        Offset(8, tabRect.center.dy),
        const Offset(0, -180),
      );
      await tester.pumpAndSettle();
      final afterLeftDrag = tester
          .state<ScrollableState>(homeScrollable)
          .position
          .pixels;
      expect(afterLeftDrag, greaterThan(beforeLeftDrag));

      await tester.dragFrom(
        Offset(tabRect.right - 8, tabRect.center.dy),
        const Offset(0, 180),
      );
      await tester.pumpAndSettle();
      final afterRightDrag = tester
          .state<ScrollableState>(homeScrollable)
          .position
          .pixels;
      expect(afterRightDrag, lessThan(afterLeftDrag));

      await tester.tap(find.text('カレンダー'));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('2026年8月'), findsOneWidget);

      await tester.tap(find.text('分別'));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(LiquidGlassSearchBar), findsOneWidget);

      await tester.tap(find.text('設定'));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('お住まいの地区'), findsOneWidget);

      await tester.tap(find.text('ホーム'));
      await tester.pumpAndSettle();
      expect(find.text('この先の収集'), findsOneWidget);
    });

    testWidgets('カレンダーで月を送ると月見出しの位置を動かさずに「今月に戻る」ピルが出て戻れる', (tester) async {
      await pumpApp(tester, const CalendarPage(), liquidGlass: true);

      expect(find.byType(AppBar), findsNothing);
      expect(find.text('今月に戻る'), findsNothing);
      final initialNextX = tester.getRect(find.byTooltip('次の月')).center.dx;

      await tester.tap(find.byTooltip('次の月'));
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(LiquidGlassPillButton, '今月に戻る'),
        findsOneWidget,
      );
      // 「今月に戻る」が出ても矢印ボタンの横位置がずれない。
      expect(
        tester.getRect(find.byTooltip('次の月')).center.dx,
        closeTo(initialNextX, 0.5),
      );

      await tester.tap(find.text('今月に戻る'));
      await tester.pumpAndSettle();
      expect(find.text('2026年8月'), findsOneWidget);
      expect(find.text('今月に戻る'), findsNothing);
    });

    testWidgets('分別画面のガラス検索欄・タッチ中のみ出る五十音ピル・出典ダイアログが動作する', (tester) async {
      final multiRowDict = WasteDictionary.fromJson({
        'source': 'テスト用の分別早見表',
        'sourceUrl': 'https://example.com/dictionary',
        'items': [
          {
            'name': 'アイロン',
            'kanaHead': 'あ',
            'category': 'nonBurnable',
            'categoryLabel': 'もえないごみ',
            'note': '',
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
            'categoryLabel': '粗大ごみ',
            'note': '直接持込みまたは戸別収集',
            'marks': ['star2'],
          },
        ],
      });

      await pumpApp(
        tester,
        const DictionaryPage(),
        dictionary: multiRowDict,
        liquidGlass: true,
      );

      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(LiquidGlassSearchBar), findsOneWidget);

      final focusLens = find.byKey(const ValueKey('kana_index_focus_lens'));
      final trackPill = find.byKey(const ValueKey('kana_index_track_pill'));

      // 通常時は五十音索引の背景ピルは出ず、現在地（「あ」）の丸いガラスレンズだけが出る。
      expect(trackPill, findsNothing);
      expect(focusLens, findsOneWidget);
      expect(
        tester.getCenter(focusLens).dy,
        closeTo(tester.getCenter(find.text('あ').last).dy, 0.5),
      );
      // 緑ベタ塗りの丸（BoxShape.circle）は使わず、太字の緑文字で現在地を示す。
      final solidCircles = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).shape == BoxShape.circle,
      );
      expect(solidCircles, findsNothing);

      // 右端の五十音索引を押さえている間だけ背景の縦長ガラスピルが浮かび、
      // ガラスレンズも触れた行（「た」）へ移動する。離すと背景ピルは消える。
      final indexTa = tester.getCenter(find.text('た').last);
      final gesture = await tester.startGesture(indexTa);
      await tester.pump();
      expect(trackPill, findsOneWidget);
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      expect(
        tester.getCenter(focusLens).dy,
        closeTo(tester.getCenter(find.text('た').last).dy, 0.5),
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(trackPill, findsNothing);
      expect(focusLens, findsOneWidget);

      // 検索語を入れると消去ボタンが出て、押すと履歴チップが残り一覧は元に戻る。
      await tester.enterText(find.byType(TextField), 'たんす');
      await tester.pumpAndSettle();
      expect(find.text('アイロン'), findsNothing);
      expect(find.byTooltip('入力を消す'), findsOneWidget);

      await tester.tap(find.byTooltip('入力を消す'));
      await tester.pumpAndSettle();
      expect(find.text('アイロン'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'たんす'), findsOneWidget);

      // 履歴チップを1タップすると再検索できる。
      await tester.tap(find.widgetWithText(InputChip, 'たんす'));
      await tester.pumpAndSettle();
      expect(find.text('アイロン'), findsNothing);
      await tester.tap(find.byTooltip('入力を消す'));
      await tester.pumpAndSettle();

      // 品目詳細のガラスシートが開く。
      await tester.tap(
        find.descendant(
          of: find.byType(ListTile),
          matching: find.textContaining('たんす'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('市の家庭ごみの出し方マニュアル'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // 出典のガラスダイアログが開き、「閉じる」ピルで閉じられる。
      await tester.tap(find.byTooltip('出典'));
      await tester.pumpAndSettle();
      expect(find.text('テスト用の分別早見表'), findsOneWidget);
      expect(find.widgetWithText(LiquidGlassPillButton, '閉じる'), findsOneWidget);
      await tester.tap(find.text('閉じる'));
      await tester.pumpAndSettle();
      expect(find.text('テスト用の分別早見表'), findsNothing);
    });

    testWidgets('設定画面の時刻ピッカー見出しがガラスモードでも中央に揃い、外観シートも動く', (tester) async {
      await pumpApp(tester, const SettingsPage(), liquidGlass: true);

      await tester.tap(find.widgetWithText(SwitchListTile, '通知'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('お知らせの時刻'));
      await tester.pumpAndSettle();

      final cancel = tester.getRect(find.text('キャンセル'));
      final title = tester.getRect(find.text('お知らせの時刻').last);
      final ok = tester.getRect(find.text('決定'));
      expect(title.center.dy, closeTo(cancel.center.dy, 0.5));
      expect(title.center.dy, closeTo(ok.center.dy, 0.5));

      final sheetWidth = tester.getSize(find.byType(CupertinoDatePicker)).width;
      expect(title.center.dx, closeTo(sheetWidth / 2, 0.5));

      await tester.tap(find.text('決定'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('外観'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ダーク'));
      await tester.pumpAndSettle();
      expect(find.text('ダーク'), findsOneWidget);
    });

    testWidgets('初回設定から収集曜日の保存までガラスボタン（戻る・主ボタン）で完走できる', (tester) async {
      await pumpRootApp(tester, area: null, liquidGlass: true);

      expect(find.byType(AreaPickerPage), findsOneWidget);
      // 初回設定の先頭画面には戻るボタンを出さない。
      expect(find.byTooltip('戻る'), findsNothing);

      await tester.enterText(find.byType(TextField), '3300001');
      await tester.pump();
      await tester.tap(find.text('探す'));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('テスト町一丁目'));
      await tester.pumpAndSettle();

      expect(find.byType(AreaEditorPage), findsOneWidget);
      // サブ画面では丸型のガラス戻るボタンと AppBar が出る。
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byTooltip('戻る'), findsOneWidget);
      final primaryBtn = find.widgetWithText(
        LiquidGlassPrimaryBarButton,
        'この設定ではじめる',
      );
      expect(primaryBtn, findsOneWidget);
      // 主ボタンは全幅の緑ベタ塗りではなく、無彩色ガラスの中央カプセルである。
      final btnSurface = tester.widget<LiquidGlassSurface>(
        find.descendant(
          of: primaryBtn,
          matching: find.byType(LiquidGlassSurface),
        ),
      );
      expect(btnSurface.tintColor, isNull);
      final surfaceRect = tester.getRect(
        find.descendant(
          of: primaryBtn,
          matching: find.byType(LiquidGlassSurface),
        ),
      );
      expect(
        surfaceRect.width,
        lessThan(TestViewport.standard.size.width - 60),
      );

      await tester.tap(find.text('この設定ではじめる'));
      await tester.pumpAndSettle();
      final tabSurfaceRect = tester.getRect(
        find.descendant(
          of: find.byType(LiquidGlassTabBar),
          matching: find.byType(LiquidGlassSurface),
        ),
      );
      // 主ボタンとボトムタブバーの高さ・下端位置が一致している。
      expect(surfaceRect.height, closeTo(tabSurfaceRect.height, 0.5));
      expect(surfaceRect.bottom, closeTo(tabSurfaceRect.bottom, 0.5));
    });

    testWidgets('下限画面サイズ（375×667）でもガラス表示の全画面・シートが溢れない', (tester) async {
      // 5区分すべてが重なる地区・分別変更お知らせ展開状態（2026年10月以降）で検証する。
      await pumpRootApp(
        tester,
        area: manyCategoryArea,
        today: DateTime(2026, 10, 6),
        viewport: TestViewport.compact,
        liquidGlass: true,
      );

      // 日詳細のガラスシート
      await tester.tap(find.textContaining('もえるごみ').first);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // カレンダー・分別・設定
      for (final tab in ['カレンダー', '分別', '設定']) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('下限画面サイズ（375×667）でも案内ページ群がガラス表示で溢れない', (tester) async {
      for (final page in <Widget>[
        const AboutPage(),
        const OversizedGuidePage(highlightedItem: '自転車'),
        const NotAcceptedGuidePage(),
        const CollectionBoxesPage(),
      ]) {
        await pumpApp(
          tester,
          page,
          viewport: TestViewport.compact,
          liquidGlass: true,
        );
        expect(find.byType(AdaptiveAppBar), findsOneWidget);
      }
    });
  });
}
