import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/app.dart';
import 'package:saitama_gomi/domain/garbage_category.dart';
import 'package:saitama_gomi/ui/caution_style.dart';
import 'package:saitama_gomi/ui/category_style.dart';

/// 注意の色が、実際の使われ方でWCAG 2.1のコントラスト比を満たすかを確かめる。
///
/// 黄色は明るい地の上で読めなくなりやすい。知らせは同じ色を薄く敷いた地の上に
/// 見出しを置き、品目の印は素の地の上に12pxの文字で置く。どちらも通常サイズの
/// 文字なので、基準は4.5:1。
double _linearize(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _relativeLuminance(Color c) =>
    0.2126 * _linearize(c.r) +
    0.7152 * _linearize(c.g) +
    0.0722 * _linearize(c.b);

double _contrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final brightness in Brightness.values) {
    final surface = SaitamaGomiApp.surfaceOf(brightness);
    final color = CautionStyle.color(brightness);

    group('${brightness.name}モードの注意の色', () {
      test('素の地の上で読める（品目の印）', () {
        expect(_contrastRatio(color, surface), greaterThanOrEqualTo(4.5));
      });

      test('同じ色を薄く敷いた地の上で読める（知らせの見出し）', () {
        final background = Color.lerp(
          surface,
          color,
          CautionStyle.backgroundAlpha,
        )!;
        expect(_contrastRatio(color, background), greaterThanOrEqualTo(4.5));
      });

      test('区分の色と同じ色ではない', () {
        // 印は区分のピルのすぐ下に出る。同じ色だと区分の一部に見える。
        for (final category in GarbageCategory.values) {
          expect(
            color,
            isNot(CategoryStyle.of(category).color(brightness)),
            reason: category.id,
          );
        }
      });
    });
  }
}
