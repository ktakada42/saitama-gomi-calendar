import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/app.dart';

void main() {
  test('名乗るときは非公式を添える', () {
    // 市の公式アプリと取り違えられないようにするため。
    expect(appName, 'さいたま市ゴミ収集カレンダー');
    expect(appNameWithDisclaimer, 'さいたま市ゴミ収集カレンダー（非公式）');
  });
}
