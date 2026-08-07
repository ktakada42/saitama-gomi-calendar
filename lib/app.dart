import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/area/area_picker_page.dart';
import 'features/shell/home_shell.dart';
import 'ui/widgets/load_failure_view.dart';
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

  static ThemeData _theme(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2F7A4F),
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      // 既定のままだと、数字・英字はSF Pro、日本語はヒラギノ角ゴという
      // フォールバックで2種類のフォントが混在し、同じ文中でも太字の出方が
      // 揃わなかった。Noto Sans JPに統一して、文字種によらず同じ見た目にする。
      fontFamily: 'Noto Sans JP',
      // Material 3 の AppBar は、コンテンツがその下に潜ると見た目を変える。
      // このアプリのヘッダーは画面名を出しているだけで、スクロール位置に応じて
      // 色が変わる必要はないので、その変化を止める。
      //
      // 効果は独立に2つあり、両方を止めないと色が変わってしまう
      // （Flutter SDK の app_bar.dart の _AppBarState.build を参照）。
      //   1. elevation に応じた surfaceTint（このアプリではシード色の緑）の重ね塗り
      //      → scrolledUnderElevation を 0 にして止める
      //   2. 背景色そのものの差し替え。既定では surfaceContainer（グレー系）になる
      //      → backgroundColor を明示すると、潜っている間も同じ色が使われる
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
    );
  }
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
      // 保存データが壊れている場合はSettingsRepositoryがnullを返して
      // 初回設定に戻すので、ここに来るのは端末のストレージ自体が読めない
      // ような場合に限られる。利用者にできることは限られるので、
      // 例外の中身は見せずに再試行の手段だけ出す。
      AsyncError() => Scaffold(
        body: LoadFailureView(
          message: '設定を読み込めませんでした。',
          onRetry: () => ref.invalidate(selectedAreaProvider),
        ),
      ),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}
