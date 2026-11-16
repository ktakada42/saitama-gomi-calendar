import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/domain/liquid_glass_support.dart';

void main() {
  group('LiquidGlassSupport.parseIosMajorVersion', () {
    test('実機・シミュレータの Version 表記からメジャー番号を取り出す', () {
      expect(
        LiquidGlassSupport.parseIosMajorVersion('Version 26.5 (Build 23F77)'),
        26,
      );
      expect(
        LiquidGlassSupport.parseIosMajorVersion(
          'Version 18.4.1 (Build 22E252)',
        ),
        18,
      );
    });

    test('短縮表記やプレフィックス付き表記でもメジャー番号を取り出す', () {
      expect(LiquidGlassSupport.parseIosMajorVersion('26.0'), 26);
      expect(LiquidGlassSupport.parseIosMajorVersion('iOS 27.1'), 27);
      expect(LiquidGlassSupport.parseIosMajorVersion('26'), 26);
    });

    test('数値を含まない文字列では null を返す', () {
      expect(LiquidGlassSupport.parseIosMajorVersion(''), isNull);
      expect(LiquidGlassSupport.parseIosMajorVersion('unknown'), isNull);
    });
  });

  group('LiquidGlassSupport.isSupported', () {
    test('iOS 26 以降は true を返す', () {
      expect(
        LiquidGlassSupport.isSupported(
          isIOS: true,
          operatingSystemVersion: 'Version 26.0 (Build 23A340)',
        ),
        isTrue,
      );
      expect(
        LiquidGlassSupport.isSupported(
          isIOS: true,
          operatingSystemVersion: 'Version 26.5 (Build 23F77)',
        ),
        isTrue,
      );
      expect(
        LiquidGlassSupport.isSupported(
          isIOS: true,
          operatingSystemVersion: 'Version 27.0 (Build 24A100)',
        ),
        isTrue,
      );
    });

    test('iOS 18〜25 は false を返し従来の表示を保つ', () {
      expect(
        LiquidGlassSupport.isSupported(
          isIOS: true,
          operatingSystemVersion: 'Version 18.0 (Build 22A3354)',
        ),
        isFalse,
      );
      expect(
        LiquidGlassSupport.isSupported(
          isIOS: true,
          operatingSystemVersion: 'Version 25.4 (Build 22F99)',
        ),
        isFalse,
      );
    });

    test('iOS 以外の OS はバージョン数値に関わらず false を返す', () {
      expect(
        LiquidGlassSupport.isSupported(
          isIOS: false,
          operatingSystemVersion: 'Linux 6.26.0',
        ),
        isFalse,
      );
      expect(
        LiquidGlassSupport.isSupported(
          isIOS: false,
          operatingSystemVersion: 'Android 26.0',
        ),
        isFalse,
      );
    });
  });
}
