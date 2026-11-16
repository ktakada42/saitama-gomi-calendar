import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../providers.dart';
import 'liquid_glass_surface.dart';

/// iOS 26 以降では透明なスクロールエッジ＋Liquid Glass ボタンのバーを返し、
/// それ以外の環境では従来の Material 3 [AppBar] をそのまま返す。
///
/// 既存のテストや画面遷移コードが `find.widgetWithText(AppBar, ...)` で見出しを
/// 参照できるよう、どちらのモードでも内部は [AppBar] で構成する。
class AdaptiveAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const AdaptiveAppBar({
    super.key,
    this.title,
    this.titleTextStyle,
    this.centerTitle,
    this.automaticallyImplyLeading = true,
    this.leading,
    this.actions,
  });

  final Widget? title;
  final TextStyle? titleTextStyle;
  final bool? centerTitle;
  final bool automaticallyImplyLeading;
  final Widget? leading;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLiquidGlass = ref.watch(liquidGlassProvider);
    if (!isLiquidGlass) {
      return AppBar(
        title: title,
        titleTextStyle: titleTextStyle,
        centerTitle: centerTitle,
        automaticallyImplyLeading: automaticallyImplyLeading,
        leading: leading,
        actions: actions,
      );
    }

    final theme = Theme.of(context);
    final bg = theme.scaffoldBackgroundColor;
    final canPop = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;

    Widget? effectiveLeading = leading;
    double? leadingWidth;
    if (effectiveLeading == null && automaticallyImplyLeading && canPop) {
      leadingWidth = 56;
      effectiveLeading = Center(
        child: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: LiquidGlassIconButton.back(
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
      );
    }

    return AppBar(
      title: title,
      titleTextStyle: titleTextStyle,
      centerTitle: centerTitle ?? true,
      automaticallyImplyLeading: false,
      leading: effectiveLeading,
      leadingWidth: leadingWidth,
      actions: actions,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      // backgroundColor を透明にすると AppBar が暗い地と誤認して白文字のステータスバーを
      // 選んでしまうため、実際の画面の明るさに合わせて明示する。
      systemOverlayStyle: theme.brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      flexibleSpace: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.65, 1.0],
              colors: [
                bg.withValues(alpha: 0.92),
                bg.withValues(alpha: 0.72),
                bg.withValues(alpha: 0.0),
              ],
            ),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// `extendBodyBehindAppBar` / `extendBody` が有効なときに、[Scaffold.body] 内の
/// スクロールビューへ上下のバー分の余白を足す。
///
/// [liquidGlass] が false のときは [base] を一切変えずに返すため、非対応 OS での
/// 既存レイアウトは 1px も変化しない。必ず [Scaffold.body] の内側（`Builder` 等）の
/// [BuildContext] を渡すこと。
EdgeInsets adaptiveScrollPadding(
  BuildContext bodyContext, {
  required bool liquidGlass,
  EdgeInsets base = EdgeInsets.zero,
}) {
  if (!liquidGlass) return base;
  final safe = MediaQuery.paddingOf(bodyContext);
  return base + EdgeInsets.only(top: safe.top, bottom: safe.bottom);
}
