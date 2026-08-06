import 'package:flutter/material.dart';

import '../domain/garbage_category.dart';

/// 区分の見た目。色・アイコン・文字の3つで区別できるようにしてある。
///
/// カレンダーのセルのように小さく表示する場所では色だけが手がかりになりがちだが、
/// 色覚特性によっては「もえるごみ（橙）」と「有害危険ごみ（赤）」が近く見える。
/// そのため必ずアイコンか短い名称を添えて使う。
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
      light: Color(0xFFD9480F),
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
      light: Color(0xFF087F5B),
      dark: Color(0xFF38D9A9),
      icon: Icons.recycling,
    ),
    GarbageCategory.recyclable2: CategoryStyle(
      light: Color(0xFF7048E8),
      dark: Color(0xFFB197FC),
      icon: Icons.newspaper,
    ),
  };

  static CategoryStyle of(GarbageCategory category) => _styles[category]!;

  static Color colorOf(GarbageCategory category, BuildContext context) =>
      of(category).color(Theme.of(context).brightness);

  static IconData iconOf(GarbageCategory category) => of(category).icon;
}
