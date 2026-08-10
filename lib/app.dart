import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/area/area_picker_page.dart';
import 'features/shell/home_shell.dart';
import 'ui/widgets/load_failure_view.dart';
import 'providers.dart';

/// アプリの正式名。画面に出す名前はここに集約する。
///
/// ホーム画面のアイコンの下だけは文字数が入りきらないので、
/// iOSのInfo.plist・AndroidのAndroidManifest.xmlで短い名前を別に持つ。
const appName = 'さいたま市ゴミ収集カレンダー';

/// 市の公式アプリと取り違えられないよう、名乗るときは「非公式」を添える。
/// アイコンの下のように文字数が入らない場所では省く。
const appNameWithDisclaimer = '$appName（非公式）';

class SaitamaGomiApp extends ConsumerWidget {
  const SaitamaGomiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 読み込み中（初回起動の一瞬）はデフォルトのライトモードで表示する。
    final themeMode = ref.watch(themeModeProvider).value ?? ThemeMode.light;

    return MaterialApp(
      title: appName,
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

  /// 地の色から積み上がる中間色の階調。
  ///
  /// M3は地の上に重なる面（メニューの背景、見出しの帯、カードなど）を
  /// この階調から取る。`surface`だけ上書きしても階調は`fromSeed`が作った
  /// ままなので、緑がかった面が残る。実際、ボトムメニューの背景は
  /// `surfaceContainer`（#EAEFE9）を使っていて薄緑のままだった。
  ///
  /// 症状の出た色を1つずつ潰すのではなく、階調ごとクリームに置き換える。
  /// 明るさの段差は`fromSeed`が作るものに合わせてあるので、
  /// 重なりの深さの表現は変わらない。
  static const _lightSurfaces = {
    'containerLowest': Color(0xFFFFFFFF),
    'containerLow': Color(0xFFF7F4EC),
    'container': Color(0xFFF2EEE4),
    'containerHigh': Color(0xFFECE8DC),
    'containerHighest': Color(0xFFE6E1D3),
    'bright': Color(0xFFFDFCF8),
    'dim': Color(0xFFDFDACC),
  };
  static const _darkSurfaces = {
    'containerLowest': Color(0xFF0F0E09),
    'containerLow': Color(0xFF1F1C14),
    'container': Color(0xFF232019),
    'containerHigh': Color(0xFF2E2A21),
    'containerHighest': Color(0xFF38342A),
    'bright': Color(0xFF3D392E),
    'dim': Color(0xFF121009),
  };

  /// テストからも同じ地の色を参照できるようにしておく。
  /// コントラスト比の検証は、実際に使う地の色の上で行わないと意味がない。
  static Color surfaceOf(Brightness brightness) =>
      brightness == Brightness.dark ? _darkSurface : _lightSurface;

  /// テストから同じテーマを組み立てられるようにしておく。
  /// 面の色の検査は、実際に使うテーマの上で行わないと意味がない。
  @visibleForTesting
  static ThemeData themeOf(Brightness brightness) => _theme(brightness);

  static ThemeData _theme(Brightness brightness) {
    final surfaces = brightness == Brightness.dark
        ? _darkSurfaces
        : _lightSurfaces;
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF2F7A4F),
          brightness: brightness,
        ).copyWith(
          surface: surfaceOf(brightness),
          surfaceContainerLowest: surfaces['containerLowest'],
          surfaceContainerLow: surfaces['containerLow'],
          surfaceContainer: surfaces['container'],
          surfaceContainerHigh: surfaces['containerHigh'],
          surfaceContainerHighest: surfaces['containerHighest'],
          surfaceBright: surfaces['bright'],
          surfaceDim: surfaces['dim'],
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

    // 地区が決まった／変わったら、ホーム画面ウィジェットの内容を書き直す。
    // ウィジェットはアプリが起動していなくても表示され続けるので、
    // アプリを開いたこの機会に先の分までまとめて渡しておく。
    // 失敗してもアプリの動作は止めない（WidgetBridge側で握りつぶす）。
    //
    // watchで今の値を取り、そのまま書き出す。listenだと変化したときしか
    // 呼ばれず、アプリを開き直しただけでは書き直されない。
    unawaited(
      ref
          .read(widgetSyncProvider)
          .sync(ref.watch(calendarProvider), DateTime.now()),
    );

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
