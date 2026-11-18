import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../providers.dart';
import 'liquid_glass_surface.dart';

/// iOS 26 以降の五十音インデックス。
///
/// iOS 実機・シミュレータでは `UiKitView` 越しに UIKit 側の `UIGlassEffect` 専用ビューを描画し、
/// 120Hz の `CADisplayLink` スプリング追従と `UISelectionFeedbackGenerator` により、
/// ボトムタブバー（`UITabBar`）と同様の連続的なガラスレンズ遷移を行う。
/// ウィジェットテスト環境や「コントラストを上げる」設定時は、同じ連続追従物理を持つ
/// Flutter 側のガラス表現にフォールバックする。
class LiquidGlassKanaIndex extends ConsumerStatefulWidget {
  const LiquidGlassKanaIndex({
    super.key,
    required this.heads,
    required this.selectedIndex,
    required this.onScrubStart,
    required this.onHeadSelected,
    required this.onScrubEnd,
  });

  /// 表示する行頭かなの並び（例：`['あ', 'か', 'さ', ...]`）。
  final List<String> heads;

  /// 現在選ばれている行のインデックス。
  final int selectedIndex;

  /// 索引に触れ始めたとき。
  final VoidCallback onScrubStart;

  /// 触れている行が変わったとき。`fromNative` が true の場合は UIKit 側で
  /// 触覚フィードバックを鳴らし済みであることを表す。
  final void Function(int index, {required bool fromNative}) onHeadSelected;

  /// 索引から指が離れたとき。
  final VoidCallback onScrubEnd;

  /// 索引の横幅。一覧側の右余白（30pt）と揃える。
  static const double width = 30;

  @override
  ConsumerState<LiquidGlassKanaIndex> createState() =>
      _LiquidGlassKanaIndexState();
}

class _LiquidGlassKanaIndexState extends ConsumerState<LiquidGlassKanaIndex>
    with SingleTickerProviderStateMixin {
  static const _viewType =
      'io.github.ktakada42.saitamagomicalendar/liquid_glass_kana_index';

  MethodChannel? _channel;
  Map<String, Object?>? _lastSentParams;

  // --- Flutter フォールバック用の連続追従状態 ---
  late final Ticker _ticker;
  Duration? _lastTickElapsed;
  int? _activePointer;
  bool _pressing = false;
  bool _dragging = false;

  double? _lensY;
  double? _targetLensY;
  double _velY = 0;
  double _lensScale = 1.0;
  double _velScale = 0;
  double _activeProgress = 0.0;
  double _lastLayoutHeight = 0;

  bool get _active => _pressing || _dragging;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void didUpdateWidget(covariant LiquidGlassKanaIndex oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_active &&
        widget.selectedIndex != oldWidget.selectedIndex &&
        _lastLayoutHeight > 0 &&
        widget.heads.isNotEmpty) {
      final itemHeight = _lastLayoutHeight / widget.heads.length;
      final clamped = widget.selectedIndex.clamp(0, widget.heads.length - 1);
      _targetLensY = clamped * itemHeight + itemHeight / 2;
      _ensureTickerRunning();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  // --- ネイティブ UIKit ブリッジ ---

  Map<String, Object?> _buildParams({
    required ThemeData theme,
    required bool touchEnabled,
  }) {
    final safeIndex = widget.heads.isEmpty
        ? 0
        : widget.selectedIndex.clamp(0, widget.heads.length - 1);
    return <String, Object?>{
      'heads': widget.heads,
      'selectedIndex': safeIndex,
      'isDark': theme.brightness == Brightness.dark,
      'tintColor': theme.colorScheme.primary.toARGB32(),
      'labelColor': theme.colorScheme.onSurface.toARGB32(),
      'mutedLabelColor': theme.colorScheme.onSurfaceVariant.toARGB32(),
      'touchEnabled': touchEnabled,
    };
  }

  bool _sameHeads(List<String>? a, List<String> b) {
    if (a == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _attachChannel(int id, Map<String, Object?> initialParams) {
    final channel = MethodChannel('${_viewType}_$id');
    channel.setMethodCallHandler((call) async {
      if (!mounted) return;
      switch (call.method) {
        case 'onScrubStart':
          widget.onScrubStart();
        case 'onSelect':
          final index = call.arguments;
          if (index is int && index >= 0 && index < widget.heads.length) {
            widget.onHeadSelected(index, fromNative: true);
          }
        case 'onScrubEnd':
          widget.onScrubEnd();
      }
    });
    _channel = channel;
    _lastSentParams = initialParams;
  }

  void _syncNativeParams(Map<String, Object?> next) {
    final channel = _channel;
    if (channel == null) return;
    final prev = _lastSentParams;
    if (prev != null &&
        _sameHeads(prev['heads'] as List<String>?, widget.heads) &&
        prev['selectedIndex'] == next['selectedIndex'] &&
        prev['isDark'] == next['isDark'] &&
        prev['tintColor'] == next['tintColor'] &&
        prev['labelColor'] == next['labelColor'] &&
        prev['mutedLabelColor'] == next['mutedLabelColor'] &&
        prev['touchEnabled'] == next['touchEnabled']) {
      return;
    }
    _lastSentParams = next;
    unawaited(channel.invokeMethod<void>('update', next));
  }

  // --- Flutter フォールバックの連続物理アニメーション ---

  void _ensureTickerRunning() {
    if (!_ticker.isActive) {
      _lastTickElapsed = null;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    final prev = _lastTickElapsed;
    _lastTickElapsed = elapsed;
    if (prev == null) return;

    final rawDt = (elapsed - prev).inMicroseconds / 1e6;
    if (rawDt <= 0) return;
    // pumpAndSettle（既定 100ms 刻み）やフレーム落ちでも発散しないよう細かく積分する。
    final clampedDt = math.min(rawDt, 0.25);
    const maxStep = 1.0 / 240.0;

    final targetY = _targetLensY;
    if (targetY == null || _lensY == null) {
      _ticker.stop();
      return;
    }

    final targetScale = _active ? 1.24 : 1.0;
    final targetActive = _active ? 1.0 : 0.0;
    final omegaY = _active ? 42.0 : 28.0;
    final zetaY = _active ? 0.90 : 0.85;

    var y = _lensY!;
    var vy = _velY;
    var s = _lensScale;
    var vs = _velScale;
    var ap = _activeProgress;

    var remaining = clampedDt;
    while (remaining > 0) {
      final dt = math.min(remaining, maxStep);
      remaining -= dt;

      final ay = omegaY * omegaY * (targetY - y) - 2.0 * zetaY * omegaY * vy;
      vy += ay * dt;
      y += vy * dt;

      const omegaS = 32.0;
      const zetaS = 0.86;
      final as_ =
          omegaS * omegaS * (targetScale - s) - 2.0 * zetaS * omegaS * vs;
      vs += as_ * dt;
      s += vs * dt;

      ap += (targetActive - ap) * math.min(1.0, dt * 18.0);
    }

    final settled =
        (targetY - y).abs() < 0.08 &&
        vy.abs() < 0.5 &&
        (targetScale - s).abs() < 0.004 &&
        vs.abs() < 0.05 &&
        (targetActive - ap).abs() < 0.01;

    setState(() {
      if (settled) {
        _lensY = targetY;
        _velY = 0;
        _lensScale = targetScale;
        _velScale = 0;
        _activeProgress = targetActive;
      } else {
        _lensY = y;
        _velY = vy;
        _lensScale = s;
        _velScale = vs;
        _activeProgress = ap;
      }
    });

    if (settled) {
      _ticker.stop();
    }
  }

  void _handleFallbackPointer(double dy, double maxHeight) {
    final count = widget.heads.length;
    if (count == 0 || maxHeight <= 0) return;
    final itemHeight = maxHeight / count;
    final minCenter = itemHeight / 2;
    final maxCenter = maxHeight - itemHeight / 2;
    final clampedY = dy.clamp(minCenter, maxCenter);

    final idx = (dy / itemHeight).floor().clamp(0, count - 1);
    setState(() {
      _targetLensY = clampedY;
    });
    _ensureTickerRunning();

    if (idx != widget.selectedIndex) {
      widget.onHeadSelected(idx, fromNative: false);
    }
  }

  void _endFallbackPointer(double maxHeight) {
    if (!_active && _activePointer == null) return;
    _activePointer = null;
    final count = widget.heads.length;
    setState(() {
      _pressing = false;
      _dragging = false;
      if (count > 0 && maxHeight > 0) {
        final itemHeight = maxHeight / count;
        final safeIdx = widget.selectedIndex.clamp(0, count - 1);
        _targetLensY = safeIdx * itemHeight + itemHeight / 2;
      }
    });
    _ensureTickerRunning();
    widget.onScrubEnd();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highContrast = MediaQuery.highContrastOf(context);
    final useNative = ref.watch(nativeLiquidGlassViewProvider) && !highContrast;

    if (useNative) {
      // モーダルシートやダイアログが前面に出ている間はネイティブビューの当たり判定を止める。
      final isCurrentRoute = ModalRoute.of(context)?.isCurrent ?? true;
      final params = _buildParams(theme: theme, touchEnabled: isCurrentRoute);
      _syncNativeParams(params);

      return SizedBox(
        width: LiquidGlassKanaIndex.width,
        child: IgnorePointer(
          ignoring: !isCurrentRoute,
          child: UiKitView(
            viewType: _viewType,
            layoutDirection: TextDirection.ltr,
            creationParams: params,
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: (id) => _attachChannel(id, params),
          ),
        ),
      );
    }

    return _buildFlutterFallback(context, theme);
  }

  Widget _buildFlutterFallback(BuildContext context, ThemeData theme) {
    final heads = widget.heads;
    if (heads.isEmpty) return const SizedBox(width: LiquidGlassKanaIndex.width);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight;
        final itemHeight = maxHeight / heads.length;
        final safeIndex = widget.selectedIndex.clamp(0, heads.length - 1);
        final selectedCenter = safeIndex * itemHeight + itemHeight / 2;

        if (_lensY == null || _targetLensY == null) {
          _lensY = selectedCenter;
          _targetLensY = selectedCenter;
          _lastLayoutHeight = maxHeight;
        } else if (_lastLayoutHeight > 0 &&
            (maxHeight - _lastLayoutHeight).abs() > 0.01) {
          // お知らせの開閉（AnimatedSize）などで索引全体の高さが変わっても、
          // レンズが対応する文字の位置からずれないよう比率を保つ。
          final ratio = maxHeight / _lastLayoutHeight;
          _lensY = _lensY! * ratio;
          _targetLensY = _active ? (_targetLensY! * ratio) : selectedCenter;
          _lastLayoutHeight = maxHeight;
        } else if (!_active && !_ticker.isActive) {
          _lensY = selectedCenter;
          _targetLensY = selectedCenter;
        }

        final lensCenterY = _lensY!;
        final baseLensSize = math.min(22.0, itemHeight * 0.88);
        final stretch = math.min(0.20, _velY.abs() / 1400.0);
        final scaleX = _lensScale * (1.0 - stretch * 0.32);
        final scaleY = _lensScale * (1.0 + stretch);

        final unselectedBaseColor = Color.lerp(
          theme.colorScheme.onSurfaceVariant,
          theme.colorScheme.onSurface,
          _activeProgress,
        )!;

        final column = Column(
          children: [
            for (var i = 0; i < heads.length; i++)
              SizedBox(
                height: itemHeight,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _buildFallbackLabel(
                      head: heads[i],
                      centerY: i * itemHeight + itemHeight / 2,
                      lensCenterY: lensCenterY,
                      itemHeight: itemHeight,
                      theme: theme,
                      unselectedBaseColor: unselectedBaseColor,
                    ),
                  ),
                ),
              ),
          ],
        );

        final stack = Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: lensCenterY - baseLensSize / 2,
              width: baseLensSize,
              height: baseLensSize,
              child: Transform.scale(
                scaleX: scaleX,
                scaleY: scaleY,
                child: const LiquidGlassSurface(
                  key: ValueKey('kana_index_focus_lens'),
                  shape: LiquidGlassShape.capsule,
                  interactive: true,
                  child: SizedBox.expand(),
                ),
              ),
            ),
            column,
          ],
        );

        return RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: <Type, GestureRecognizerFactory>{
            // 親にスクロール可能なウィジェットが増えても縦ドラッグを奪われないようにする。
            VerticalDragGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  VerticalDragGestureRecognizer
                >(
                  () =>
                      VerticalDragGestureRecognizer()
                        ..dragStartBehavior = DragStartBehavior.down,
                  (instance) {
                    instance
                      ..onDown = (_) {}
                      ..onStart = (_) {}
                      ..onUpdate = (_) {}
                      ..onEnd = (_) {}
                      ..onCancel = () {};
                  },
                ),
          },
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) {
              if (_activePointer != null) return;
              _activePointer = e.pointer;
              _pressing = true;
              widget.onScrubStart();
              _handleFallbackPointer(e.localPosition.dy, maxHeight);
            },
            onPointerMove: (e) {
              if (e.pointer != _activePointer) return;
              _dragging = true;
              _handleFallbackPointer(e.localPosition.dy, maxHeight);
            },
            onPointerUp: (e) {
              if (e.pointer != _activePointer) return;
              _endFallbackPointer(maxHeight);
            },
            onPointerCancel: (e) {
              if (e.pointer != _activePointer) return;
              _endFallbackPointer(maxHeight);
            },
            child: SizedBox(
              width: LiquidGlassKanaIndex.width,
              child: _active
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: LiquidGlassSurface(
                        key: const ValueKey('kana_index_track_pill'),
                        shape: LiquidGlassShape.capsule,
                        interactive: true,
                        child: stack,
                      ),
                    )
                  : stack,
            ),
          ),
        );
      },
    );
  }

  Widget _buildFallbackLabel({
    required String head,
    required double centerY,
    required double lensCenterY,
    required double itemHeight,
    required ThemeData theme,
    required Color unselectedBaseColor,
  }) {
    final dist = (centerY - lensCenterY).abs() / math.max(1.0, itemHeight);
    final proximity = (1.0 - dist).clamp(0.0, 1.0);
    // 境界での折れ曲がりを無くす smoothstep 補間。
    final t = proximity * proximity * (3.0 - 2.0 * proximity);

    final color = Color.lerp(
      unselectedBaseColor,
      theme.colorScheme.primary,
      t,
    )!;
    final weight = FontWeight.lerp(FontWeight.w400, FontWeight.w700, t)!;
    final maxBoost = 0.04 + 0.14 * _activeProgress;
    final scale = 1.0 + maxBoost * t;

    return Transform.scale(
      scale: scale,
      child: SizedBox(
        width: 22,
        height: 22,
        child: Center(
          child: Text(
            head,
            style: theme.textTheme.labelMedium?.copyWith(
              height: 1.0,
              fontWeight: weight,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}
