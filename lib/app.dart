import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/area/area_picker_page.dart';
import 'features/shell/home_shell.dart';
import 'providers.dart';

class SaitamaGomiApp extends ConsumerWidget {
  const SaitamaGomiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 読み込み中（初回起動の一瞬）はデフォルトのライトモードで表示する。
    final themeMode = ref.watch(themeModeProvider).value ?? ThemeMode.light;

    return MaterialApp(
      title: 'さいたまごみカレンダー',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: themeMode,
      locale: const Locale('ja'),
      supportedLocales: const [Locale('ja')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _Root(),
    );
  }

  static ThemeData _theme(Brightness brightness) => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF2F7A4F),
      brightness: brightness,
    ),
    useMaterial3: true,
    // Material 3 の AppBar は、コンテンツがその下に潜ると
    // surfaceTint（＝シード色の緑）を重ねて浮き上がって見せる仕様になっている。
    // このアプリのヘッダーは画面名を出しているだけで、スクロール位置に応じて
    // 色が変わる必要はなく、下方向にスクロールするたびにヘッダーが緑に光って
    // 見えるだけなので、この着色を止める。
    appBarTheme: const AppBarTheme(elevation: 0, scrolledUnderElevation: 0),
  );
}

/// 地区が未設定なら初回設定へ、設定済みなら本体へ。
class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final area = ref.watch(selectedAreaProvider);
    return switch (area) {
      AsyncData(:final value) =>
        value == null
            ? const AreaPickerPage(isOnboarding: true)
            : const HomeShell(),
      AsyncError(:final error) => Scaffold(
        body: Center(child: Text('設定の読み込みに失敗しました\n$error')),
      ),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}
