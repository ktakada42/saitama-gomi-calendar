import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/app.dart';

/// 地とその上に重なる面が緑がからないことを確かめる。
///
/// `ColorScheme.fromSeed`は中間色もシード色（緑）の色相へ寄せる。
/// これまで薄緑が出るたびに、その色（surface、primaryContainer、
/// secondaryContainer、surfaceContainer…）を1つずつ潰してきたが、
/// 潰し漏れが残るたびに同じ指摘を受けた。役割ごとではなく、
/// 面に使われる色を総なめにして検査する。
void main() {
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
