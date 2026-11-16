import 'package:material_ui/material_ui.dart';

import 'liquid_glass_surface.dart';

/// [liquidGlass] が有効なときは上隅を大きく丸めた Liquid Glass のハーフシートとして出し、
/// 無効なときは従来の Material 3 ボトムシートをそのまま出す。
Future<T?> showAdaptiveModalSheet<T>({
  required BuildContext context,
  required bool liquidGlass,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  BoxConstraints? constraints,
}) {
  if (!liquidGlass) {
    return showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      isScrollControlled: isScrollControlled,
      constraints: constraints,
      builder: builder,
    );
  }

  final effectiveConstraints = BoxConstraints(
    minWidth: double.infinity,
    maxWidth: constraints?.maxWidth ?? double.infinity,
    minHeight: constraints?.minHeight ?? 0,
    maxHeight: constraints?.maxHeight ?? double.infinity,
  );

  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    elevation: 0,
    showDragHandle: false,
    isScrollControlled: isScrollControlled,
    constraints: effectiveConstraints,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final isDark = theme.brightness == Brightness.dark;
      // クリーム基調の紙色（g <= r）を薄く混ぜ、ガラスの透過感と文字の読みやすさを両立する。
      final sheetTint = theme.colorScheme.surfaceContainerLow.withValues(
        alpha: isDark ? 0.82 : 0.84,
      );

      return SizedBox(
        width: double.infinity,
        child: LiquidGlassSurface(
          shape: LiquidGlassShape.topRounded,
          cornerRadius: 32,
          tintColor: sheetTint,
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SheetGrabber(),
                Flexible(child: builder(sheetContext)),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _SheetGrabber extends StatelessWidget {
  const _SheetGrabber();

  @override
  Widget build(BuildContext context) {
    final handleColor = Theme.of(
      context,
    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.36);

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: Center(
        child: Container(
          width: 36,
          height: 5,
          decoration: BoxDecoration(
            color: handleColor,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}

/// [liquidGlass] が有効なときは Liquid Glass 面の角丸ダイアログを出し、
/// 無効なときは従来の [AlertDialog] をそのまま出す。
Future<T?> showAdaptiveAlertDialog<T>({
  required BuildContext context,
  required bool liquidGlass,
  required Widget title,
  required Widget content,
  required List<Widget> actions,
}) {
  if (!liquidGlass) {
    return showDialog<T>(
      context: context,
      builder: (_) =>
          AlertDialog(title: title, content: content, actions: actions),
    );
  }

  return showDialog<T>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      final isDark = theme.brightness == Brightness.dark;
      final dialogTint = theme.colorScheme.surfaceContainerLow.withValues(
        alpha: isDark ? 0.82 : 0.85,
      );

      return Dialog(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: LiquidGlassSurface(
            shape: LiquidGlassShape.rounded,
            cornerRadius: 28,
            tintColor: dialogTint,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DefaultTextStyle.merge(
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    child: title,
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: DefaultTextStyle.merge(
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                      child: content,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: actions,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
