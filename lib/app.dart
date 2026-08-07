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

  /// 画面の地の色。
  ///
  /// `ColorScheme.fromSeed`は中間色もシード色の色相に寄せるので、緑をシードに
  /// すると地の色まで緑がかる（ライトなら#F6FBF3、ダークなら#0F1511）。
  /// ごみを扱うアプリの地としては紙に近いクリームのほうが素直なので上書きする。
  ///
  /// もっと温かみのある色（#F7F3E9など）も検討したが、区分色との組み合わせで
  /// WCAG AAのコントラスト比を割ってしまう（もえるごみで4.42、基準は4.5）。
  /// 白寄りに留めることで、区分色を触らずに基準を満たしている
  /// （検証は`test/ui/category_style_test.dart`）。
  static const _lightSurface = Color(0xFFFCFAF5);
  static const _darkSurface = Color(0xFF17150F);

  /// 「選ばれている」ことを示す面の色。
  ///
  /// これも`fromSeed`任せだと緑シードから薄緑（ライトで#B0F1C3・#D1E8D5）が
  /// 生成され、ボトムメニューの選択インジケータや郵便番号の候補タイルが
  /// 淡い緑に染まる。地をクリームにした（surface）のと同じ理由で、
  /// 紙に近い色みに寄せる。
  ///
  /// primaryContainerは「今どれが選ばれているか」を示す強めの面、
  /// secondaryContainerはインジケータのような控えめな面に使われる。
  static const _lightPrimaryContainer = Color(0xFFE8E2D2);
  static const _lightSecondaryContainer = Color(0xFFEDE8DC);
  static const _darkPrimaryContainer = Color(0xFF3A362B);
  static const _darkSecondaryContainer = Color(0xFF2C2921);

  /// テストからも同じ地の色を参照できるようにしておく。
  /// コントラスト比の検証は、実際に使う地の色の上で行わないと意味がない。
  static Color surfaceOf(Brightness brightness) =>
      brightness == Brightness.dark ? _darkSurface : _lightSurface;

  static ThemeData _theme(Brightness brightness) {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF2F7A4F),
          brightness: brightness,
        ).copyWith(
          surface: surfaceOf(brightness),
          primaryContainer: brightness == Brightness.dark
              ? _darkPrimaryContainer
              : _lightPrimaryContainer,
          secondaryContainer: brightness == Brightness.dark
              ? _darkSecondaryContainer
              : _lightSecondaryContainer,
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
