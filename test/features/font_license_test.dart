import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/main.dart' as app;

void main() {
  testWidgets('同梱フォントの許諾がライセンス一覧に載る', (tester) async {
    // pubspec.yamlのdependenciesから入るものはFlutterが自動で拾うが、
    // assetsとして持ち込んだフォントは拾われないので自分で登録している。
    app.registerFontLicense();

    final entries = await LicenseRegistry.licenses.toList();
    final font = entries.where((e) => e.packages.contains('Noto Sans JP'));
    expect(font, hasLength(1));
    expect(
      font.single.paragraphs.map((p) => p.text).join(),
      contains('SIL OPEN FONT LICENSE'),
    );
  });
}
