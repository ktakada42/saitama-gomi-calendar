import 'package:flutter/material.dart';

import '../domain/garbage_category.dart';

/// 区分の見た目。色・アイコン・文字の3つで区別できるようにしてある。
///
/// カレンダーのセルのように小さく表示する場所では色だけが手がかりになりがちだが、
/// 色覚特性によっては「もえるごみ（橙）」と「有害危険ごみ（赤）」が近く見える。
/// そのため必ずアイコンか短い名称を添えて使う。
///
/// light側の3色（burnable・recyclable1・recyclable2）は、元の色そのままだと
/// WCAG 2.1のコントラスト比を満たさない場面があったため、色相・彩度を保った
/// まま明度だけを下げてある。`CategoryBadge`・カレンダーの区分帯は、区分の色を
/// 文字色にしつつ、同じ色を薄く敷いた背景（12%・18%alpha）の上に置く実装なので、
/// 前景と背景が似た色になりコントラストが弱まりやすい。最も厳しい18%alpha背景
/// （カレンダーの区分帯）で4.5:1（通常テキストの基準）を超えるように調整した。
/// dark側は元の色のままで基準を満たしている。この検証は
/// test/ui/category_style_test.dartで自動テストとして常設している。
class CategoryStyle {
  const CategoryStyle({
    required this.light,
    required this.dark,
    required this.icon,
  });

  final Color light;
  final Color dark;
  final IconData icon;

  Color color(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  static const _styles = <GarbageCategory, CategoryStyle>{
    GarbageCategory.burnable: CategoryStyle(
      light: Color(0xFFA9380C), // 元は0xFFD9480F。a11y調整済み（上記コメント参照）
      dark: Color(0xFFFF922B),
      icon: Icons.local_fire_department,
    ),
    GarbageCategory.nonBurnable: CategoryStyle(
      light: Color(0xFF364FC7),
      dark: Color(0xFF748FFC),
      icon: Icons.handyman,
    ),
    GarbageCategory.hazardous: CategoryStyle(
      light: Color(0xFFA61E4D),
      dark: Color(0xFFF06595),
      icon: Icons.warning_amber_rounded,
    ),
    GarbageCategory.recyclable1: CategoryStyle(
      light: Color(0xFF076C4D), // 元は0xFF087F5B。a11y調整済み（上記コメント参照）
      dark: Color(0xFF38D9A9),
      icon: Icons.recycling,
    ),
    GarbageCategory.recyclable2: CategoryStyle(
      light: Color(0xFF6438E6), // 元は0xFF7048E8。a11y調整済み（上記コメント参照）
      dark: Color(0xFFB197FC),
      icon: Icons.newspaper,
    ),
  };

  static CategoryStyle of(GarbageCategory category) => _styles[category]!;

  static Color colorOf(GarbageCategory category, BuildContext context) =>
      of(category).color(Theme.of(context).brightness);

  static IconData iconOf(GarbageCategory category) => of(category).icon;
}
