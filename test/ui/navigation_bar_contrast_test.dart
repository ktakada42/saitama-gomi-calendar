import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saitama_gomi/app.dart';
import 'package:saitama_gomi/features/shell/home_shell.dart';

import '../support/test_app.dart';

/// ボトムメニュー（NavigationBar）の選択状態がWCAG 2.1 AAのコントラスト基準を
/// 満たしつつ、面の塗りはクリーム階調を保っていることを確かめる。
double _linearize(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _relativeLuminance(Color c) =>
    0.2126 * _linearize(c.r) +
    0.7152 * _linearize(c.g) +
    0.0722 * _linearize(c.b);

double _contrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  const selectedState = <WidgetState>{WidgetState.selected};
  const unselectedState = <WidgetState>{};

  for (final brightness in Brightness.values) {
    group('${brightness.name}モードのボトムメニュー配色', () {
      final theme = SaitamaGomiApp.themeOf(brightness);
      final navTheme = theme.navigationBarTheme;
      final barColor = navTheme.backgroundColor!;
      final pillColor = navTheme.indicatorColor!;
      final shape = navTheme.indicatorShape! as StadiumBorder;
      final borderColor = shape.side.color;

      final selectedIconColor = navTheme.iconTheme!
          .resolve(selectedState)!
          .color!;
      final unselectedIconColor = navTheme.iconTheme!
          .resolve(unselectedState)!
          .color!;
      final selectedLabelStyle = navTheme.labelTextStyle!.resolve(
        selectedState,
      )!;
      final unselectedLabelStyle = navTheme.labelTextStyle!.resolve(
        unselectedState,
      )!;

      test('ピルの塗りは緑に寄っていない', () {
        final argb = pillColor.toARGB32();
        final r = (argb >> 16) & 0xFF;
        final g = (argb >> 8) & 0xFF;
        final b = argb & 0xFF;
        expect(g, lessThanOrEqualTo(r));
        expect(b, lessThanOrEqualTo(g));
      });

      test('選択ピルの枠線はバー背景・ピル塗りの双方と3:1以上のコントラストを持つ（WCAG 1.4.11）', () {
        expect(shape.side.width, greaterThanOrEqualTo(1.5));
        expect(
          _contrastRatio(borderColor, barColor),
          greaterThanOrEqualTo(3.0),
        );
        expect(
          _contrastRatio(borderColor, pillColor),
          greaterThanOrEqualTo(3.0),
        );
      });

      test('選択・未選択アイコンはそれぞれの背景と3:1以上のコントラストを持つ（WCAG 1.4.11）', () {
        expect(
          _contrastRatio(selectedIconColor, pillColor),
          greaterThanOrEqualTo(3.0),
        );
        expect(
          _contrastRatio(unselectedIconColor, barColor),
          greaterThanOrEqualTo(3.0),
        );
      });

      test('選択・未選択ラベルはバー背景と4.5:1以上のコントラストを持ち、太さでも区別できる（WCAG 1.4.3）', () {
        expect(
          _contrastRatio(selectedLabelStyle.color!, barColor),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrastRatio(unselectedLabelStyle.color!, barColor),
          greaterThanOrEqualTo(4.5),
        );
        expect(selectedLabelStyle.fontWeight, FontWeight.bold);
        expect(unselectedLabelStyle.fontWeight, FontWeight.w500);
      });
    });
  }

  testWidgets('タブを切り替えると選択先のピル枠線と太字ラベルが切り替わる', (tester) async {
    await pumpApp(tester, const HomeShell());
    final scheme = SaitamaGomiApp.themeOf(Brightness.light).colorScheme;
    final navBar = find.byType(NavigationBar);
    final dictionaryNavLabel = find.descendant(
      of: navBar,
      matching: find.text('分別'),
    );
    final homeNavLabel = find.descendant(
      of: navBar,
      matching: find.text('ホーム'),
    );

    // 形状差のない「分別」タブへ切り替えても、色・太字・枠線で識別できることを確かめる。
    await tester.tap(dictionaryNavLabel);
    await tester.pumpAndSettle();

    final dictionaryLabel = tester.widget<Text>(dictionaryNavLabel);
    final homeLabel = tester.widget<Text>(homeNavLabel);
    expect(dictionaryLabel.style?.color, scheme.primary);
    expect(dictionaryLabel.style?.fontWeight, FontWeight.bold);
    expect(homeLabel.style?.color, scheme.onSurfaceVariant);
    expect(homeLabel.style?.fontWeight, FontWeight.w500);

    final indicators = tester
        .widgetList<NavigationIndicator>(find.byType(NavigationIndicator))
        .toList();
    expect(indicators, hasLength(4));
    expect(
      indicators[2].shape,
      StadiumBorder(side: BorderSide(color: scheme.primary, width: 1.5)),
    );
  });
}
