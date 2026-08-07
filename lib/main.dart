import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicense();
  // カレンダーも一覧も縦に読む画面なので縦固定にする。
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const ProviderScope(child: SaitamaGomiApp()));
}

/// 同梱フォントの許諾をライセンス一覧に載せる。
///
/// pubspec.yamlのdependenciesから入るものはFlutterが自動で拾うが、
/// assetsとして自分で持ち込んだフォントは拾われない。OFLは許諾表示を
/// 求めているので、ここで登録する。
@visibleForTesting
void registerFontLicense() {
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString(
      'assets/fonts/NotoSansJP-OFL.txt',
    );
    yield LicenseEntryWithLineBreaks(const ['Noto Sans JP'], license);
  });
}
