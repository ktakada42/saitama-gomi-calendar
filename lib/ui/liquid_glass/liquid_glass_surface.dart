import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../providers.dart';

/// ガラス面の角の形。ネイティブ側の `UICornerConfiguration` と対応する。
enum LiquidGlassShape {
  /// 高さに合わせて両端を半円にするカプセル型（ボタン・検索欄・索引など）。
  capsule('capsule'),

  /// 四隅すべてを指定半径で丸める（ダイアログ・カード状の浮き面など）。
  rounded('rounded'),

  /// 上の二隅だけを丸める（画面下端から出るハーフシートなど）。
  topRounded('topRounded');

  const LiquidGlassShape(this.wireName);

  final String wireName;
}

/// ガラスの質感。`UIGlassEffect.Style` と対応する。
enum LiquidGlassStyle {
  regular('regular'),
  clear('clear');

  const LiquidGlassStyle(this.wireName);

  final String wireName;
}

/// iOS 26 以降の Liquid Glass 面を子ウィジェットの背面に敷く。
///
/// iOS 実機・シミュレータでは `UiKitView` 越しに UIKit 純正の
/// `UIVisualEffectView(effect: UIGlassEffect)` を描画する。ヘッドレスの
/// ウィジェットテスト環境や「コントラストを上げる」設定が有効な場合は、
/// Flutter 側のぼかし・半透明面で同じ輪郭を描く。
class LiquidGlassSurface extends ConsumerStatefulWidget {
  const LiquidGlassSurface({
    super.key,
    required this.child,
    this.shape = LiquidGlassShape.capsule,
    this.style = LiquidGlassStyle.regular,
    this.cornerRadius = 24,
    this.tintColor,
    this.interactive = false,
  });

  final Widget child;
  final LiquidGlassShape shape;
  final LiquidGlassStyle style;
  final double cornerRadius;
  final Color? tintColor;
  final bool interactive;

  @override
  ConsumerState<LiquidGlassSurface> createState() => _LiquidGlassSurfaceState();
}

class _LiquidGlassSurfaceState extends ConsumerState<LiquidGlassSurface> {
  static const _viewType =
      'io.github.ktakada42.saitamagomicalendar/liquid_glass_surface';

  MethodChannel? _channel;
  Map<String, Object?>? _lastSentParams;

  Map<String, Object?> _buildParams(Brightness brightness) {
    return <String, Object?>{
      'style': widget.style.wireName,
      'interactive': widget.interactive,
      'shape': widget.shape.wireName,
      'cornerRadius': widget.cornerRadius,
      'tintColor': widget.tintColor?.toARGB32(),
      'isDark': brightness == Brightness.dark,
    };
  }

  void _syncNativeParams(Map<String, Object?> next) {
    final channel = _channel;
    if (channel == null) return;
    final prev = _lastSentParams;
    if (prev != null &&
        prev['style'] == next['style'] &&
        prev['interactive'] == next['interactive'] &&
        prev['shape'] == next['shape'] &&
        prev['cornerRadius'] == next['cornerRadius'] &&
        prev['tintColor'] == next['tintColor'] &&
        prev['isDark'] == next['isDark']) {
      return;
    }
    _lastSentParams = next;
    unawaited(channel.invokeMethod<void>('update', next));
  }

  BorderRadius _borderRadius() => switch (widget.shape) {
    LiquidGlassShape.capsule => BorderRadius.circular(999),
    LiquidGlassShape.rounded => BorderRadius.circular(widget.cornerRadius),
    LiquidGlassShape.topRounded => BorderRadius.vertical(
      top: Radius.circular(widget.cornerRadius),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highContrast = MediaQuery.highContrastOf(context);
    final useNative = ref.watch(nativeLiquidGlassViewProvider) && !highContrast;

    if (useNative) {
      final params = _buildParams(theme.brightness);
      _syncNativeParams(params);

      return Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: UiKitView(
                viewType: _viewType,
                layoutDirection: TextDirection.ltr,
                creationParams: params,
                creationParamsCodec: const StandardMessageCodec(),
                onPlatformViewCreated: (id) {
                  _channel = MethodChannel('${_viewType}_$id');
                  _lastSentParams = params;
                },
              ),
            ),
          ),
          widget.child,
        ],
      );
    }

    // テスト環境および高コントラスト時の Flutter 描画フォールバック。
    final radius = _borderRadius();
    final isDark = theme.brightness == Brightness.dark;
    final baseFill =
        widget.tintColor ??
        (isDark
            ? theme.colorScheme.surfaceContainerHigh.withValues(
                alpha: highContrast ? 0.96 : 0.76,
              )
            : theme.colorScheme.surfaceBright.withValues(
                alpha: highContrast ? 0.96 : 0.78,
              ));
    final rimColor = isDark
        ? Colors.white.withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.72);
    final outerShadowColor = Colors.black.withValues(
      alpha: isDark ? 0.28 : 0.08,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: outerShadowColor,
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: highContrast ? 0 : 20,
            sigmaY: highContrast ? 0 : 20,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: baseFill,
              borderRadius: radius,
              border: Border.all(color: rimColor, width: 0.8),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// 押したときにわずかに縮んで手応えを返す共通ラッパー。
class _PressableScale extends StatefulWidget {
  const _PressableScale({
    required this.onPressed,
    required this.child,
    this.tooltip,
    this.semanticLabel,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final String? tooltip;
  final String? semanticLabel;

  @override
  State<_PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<_PressableScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    Widget content = Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _pressed ? 0.93 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: widget.child,
        ),
      ),
    );

    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      content = Tooltip(message: widget.tooltip!, child: content);
    }
    return content;
  }
}

/// ナビゲーションバーの「戻る」や右上アクションに使う丸型の Liquid Glass ボタン。
class LiquidGlassIconButton extends StatelessWidget {
  const LiquidGlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 40,
    this.iconSize = 20,
  });

  /// iOS 標準のシェブロン付き「戻る」ボタンを作る。
  factory LiquidGlassIconButton.back({
    Key? key,
    required VoidCallback onPressed,
  }) {
    return LiquidGlassIconButton(
      key: key,
      icon: CupertinoIcons.back,
      iconSize: 21,
      tooltip: '戻る',
      onPressed: onPressed,
    );
  }

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onPressed != null;
    final fg = enabled
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurface.withValues(alpha: 0.32);

    return _PressableScale(
      onPressed: onPressed,
      tooltip: tooltip,
      semanticLabel: tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: LiquidGlassSurface(
          shape: LiquidGlassShape.capsule,
          interactive: enabled,
          child: Center(
            child: Icon(icon, size: iconSize, color: fg),
          ),
        ),
      ),
    );
  }
}

/// 「今月に戻る」やシートのボタンに使うカプセル型の Liquid Glass ボタン。
class LiquidGlassPillButton extends StatelessWidget {
  const LiquidGlassPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.prominent = false,
    this.height = 36,
    this.horizontalPadding = 14,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// 決定アクションのように主色で色付けするか。
  final bool prominent;
  final double height;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onPressed != null;
    final tint = prominent && enabled
        ? theme.colorScheme.primary.withValues(alpha: 0.85)
        : null;
    final fg = prominent && enabled
        ? theme.colorScheme.onPrimary
        : enabled
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withValues(alpha: 0.38);

    return _PressableScale(
      onPressed: onPressed,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height),
        child: LiquidGlassSurface(
          shape: LiquidGlassShape.capsule,
          interactive: enabled,
          tintColor: tint,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: 6,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: fg,
                    fontWeight: prominent ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// iOS 26 純正 `UITabBar` の浮遊カプセルと下端位置・左右インセットを揃える余白。
///
/// Home Indicator がある端末（`bottomInset == 34pt`）では純正タブバーの底辺が
/// 画面下端から約 21pt の位置に置かれるため、`SafeArea`（34pt）のままよりも
/// 13pt 低く沈めて高さを一致させる。
EdgeInsets liquidGlassBottomBarMargin(BuildContext context) {
  final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
  final bottom = bottomInset > 0 ? math.max(12.0, bottomInset - 13.0) : 12.0;
  return EdgeInsets.fromLTRB(21, 0, 21, bottom);
}

/// 画面下部に浮かぶ主アクションボタン（「保存する」「この設定ではじめる」など）。
///
/// Apple HIG に従い、全幅のベタ塗りバーではなく無彩色の透明ガラス＋主色（緑）の
/// 太字ラベルを持つ中央寄せカプセルとし、高さ（60pt）もボトムタブバーと揃える。
class LiquidGlassPrimaryBarButton extends StatelessWidget {
  const LiquidGlassPrimaryBarButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  /// 純正 `UITabBar` のカプセル高さ（約 61pt）に揃えた高さ。
  static const double height = 60;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onPressed != null;
    final fg = enabled
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withValues(alpha: 0.38);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: _PressableScale(
            onPressed: onPressed,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: 200,
                minHeight: height,
                maxHeight: height,
              ),
              child: LiquidGlassSurface(
                shape: LiquidGlassShape.capsule,
                interactive: enabled,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Center(
                    widthFactor: 1.0,
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: fg,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
