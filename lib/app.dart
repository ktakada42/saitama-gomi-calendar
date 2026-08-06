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
      scrollBehavior: const _AppScrollBehavior(),
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
  );
}

/// 縦画面固定・iOSファーストのこのアプリでは、Android由来の
/// オーバースクロール時の発光（グロー）表示は出さず、iOSと同じ
/// バウンス挙動だけにする。
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
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
