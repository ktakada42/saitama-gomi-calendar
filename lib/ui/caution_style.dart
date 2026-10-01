import 'package:flutter/material.dart';

/// 「注意して読んでほしい」ことを示す色。
///
/// 分別の変更の知らせと、品目に付いた印（「大きさで出し方が変わる」
/// 「プラスチック製で30cm未満なら資源物1類」など）に使う。どちらも、
/// 一覧の区分だけを見て出すと間違えることを伝えるもので、補足ではない。
/// アプリの主色（緑）で出すと「できる・よい」の意味に読めてしまうので、
/// 注意の色（黄）にする。
///
/// 赤にはしない。もえるごみ（橙）・有害危険ごみ（赤）の区分色と紛れるうえ、
/// 「出してはいけない」の意味に読める。
///
/// 黄色そのものはクリームの地の上では読めないので、lightは明度を落とした
/// 黄土色にしてある。知らせは同じ色を10%で敷いた地の上に文字を置くので、
/// そこで4.5:1（WCAG 2.1の通常テキストの基準）を超える色を選んだ。
/// この検証は test/ui/caution_style_test.dart に常設している。
abstract final class CautionStyle {
  static const light = Color(0xFF7A5600);
  static const dark = Color(0xFFFFD43B);

  /// 知らせの地に敷く濃さ。
  static const backgroundAlpha = 0.10;

  static Color color(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  static Color colorOf(BuildContext context) =>
      color(Theme.of(context).brightness);
}
