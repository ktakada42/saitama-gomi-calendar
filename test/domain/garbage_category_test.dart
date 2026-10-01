import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/domain/garbage_category.dart';

void main() {
  final before = DateTime(2026, 9, 30);
  final after = DateTime(2026, 10, 1);

  group('プラスチックの分別変更の前後で、区分の説明が変わる', () {
    test('資源物1類は、変更の前は容器包装プラスチック', () {
      // カレンダーは過去の月も見られる。9月以前の日に「プラスチック資源」と
      // 出すと、当時は集めていなかったものを載せることになる。
      const category = GarbageCategory.recyclable1;
      expect(category.examplesOn(before), contains('容器包装プラスチック'));
      expect(category.examplesOn(before), isNot(contains('プラスチック資源')));
      expect(category.examplesOn(after), contains('プラスチック資源'));
      expect(category.howToOn(before), isNot(contains('プラスチック資源')));
      expect(category.howToOn(after), contains('プラスチック100％'));
    });

    test('もえるごみは、変更の前はプラスチック製品を含む', () {
      const category = GarbageCategory.burnable;
      expect(category.examplesOn(before), contains('容器包装以外のプラスチック製品'));
      expect(category.examplesOn(after), contains('汚れの落ちないプラスチック'));
    });

    test('もえないごみに30cm以上のプラスチック製品が入るのは、変更のあと', () {
      const category = GarbageCategory.nonBurnable;
      expect(category.examplesOn(before), isNot(contains('30cm以上のプラスチック製品')));
      expect(category.examplesOn(after), contains('30cm以上のプラスチック製品'));
    });

    test('変更に関わらない区分は、前後で同じ', () {
      for (final category in [
        GarbageCategory.hazardous,
        GarbageCategory.recyclable2,
      ]) {
        expect(category.examplesOn(before), category.examplesOn(after));
        expect(category.howToOn(before), category.howToOn(after));
      }
    });

    test('変更で文が変わらなかった出し方は、前後で同じ', () {
      expect(
        GarbageCategory.burnable.howToOn(before),
        GarbageCategory.burnable.howToOn(after),
      );
    });
  });
}
