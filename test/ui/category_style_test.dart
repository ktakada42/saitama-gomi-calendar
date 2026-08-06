import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/domain/garbage_category.dart';
import 'package:saitama_gomi/ui/category_style.dart';

/// 区分の色が、実際の使われ方でWCAG 2.1のコントラスト比を満たすかを確かめる。
///
/// 色そのものではなく「その色がどんな背景の上に置かれるか」まで含めて検証する。
/// `CategoryBadge`・カレンダーの区分帯（`_CategoryStrip`）は、区分の色を文字色に
/// しつつ、同じ色を薄く敷いた背景（12%・18%alpha）の上に置く実装になっており、
/// 前景と背景が似た色になるぶんコントラストが弱まりやすい。この2箇所を
/// 実際の背景色（`ColorScheme.fromSeed`が生成する実際の値）で計算して確かめる。

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

Color _alphaOver(Color fg, double alpha, Color bg) =>
    Color.lerp(bg, fg, alpha)!;

void main() {
  for (final brightness in Brightness.values) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2F7A4F),
      brightness: brightness,
    );
    final surface = scheme.surface;

    group('${brightness.name}モードの区分色', () {
      for (final category in GarbageCategory.values) {
        final color = CategoryStyle.of(category).color(brightness);

        test('${category.id}: カレンダーの区分帯（18%alpha背景、通常テキスト基準）', () {
          final background = _alphaOver(color, 0.18, surface);
          final ratio = _contrastRatio(color, background);
          // WCAG AA、通常サイズのテキスト。カレンダーの区分帯は10pxと小さいため
          // 「大きい文字」の緩い基準（3:1）は使えない。
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason:
                'カレンダーの区分帯は色 $color を同じ色の18%alpha背景の上に'
                '文字として置くため、通常テキストのAA基準(4.5:1)を満たす必要がある'
                '（実測: ${ratio.toStringAsFixed(2)}）',
          );
        });

        test('${category.id}: バッジ（12%alpha背景、通常テキスト基準）', () {
          final background = _alphaOver(color, 0.12, surface);
          final ratio = _contrastRatio(color, background);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason:
                'CategoryBadgeは色 $color を同じ色の12%alpha背景の上に'
                '文字として置くため、通常テキストのAA基準(4.5:1)を満たす必要がある'
                '（実測: ${ratio.toStringAsFixed(2)}）',
          );
        });

        test('${category.id}: 素の背景上（大きい文字の基準）', () {
          final ratio = _contrastRatio(color, surface);
          // ホーム画面の区分名はheadlineSmall(24px相当)で表示するので、
          // 「大きい文字」の基準（3:1）でよい。
          expect(
            ratio,
            greaterThanOrEqualTo(3.0),
            reason:
                'ホーム画面では色 $color を背景 $surface の上に'
                '大きな文字として直接置くため、3:1以上が必要'
                '（実測: ${ratio.toStringAsFixed(2)}）',
          );
        });
      }
    });
  }
}
