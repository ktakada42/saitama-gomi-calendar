import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../providers.dart';
import 'liquid_glass_surface.dart';

class _TabSpec {
  const _TabSpec({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// iOS 26 以降のボトムタブバー。
///
/// iOS 実機・シミュレータでは UIKit 純正の `UITabBarController` を `UiKitView` 越しに
/// 表示し、カプセル型のガラス屈折やドラッグ選択レンズなど Apple 純正の挙動をそのまま使う。
/// ウィジェットテストや高コントラスト設定時は Flutter 側のカプセル型バーにフォールバックする。
class LiquidGlassTabBar extends ConsumerStatefulWidget {
  const LiquidGlassTabBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  ConsumerState<LiquidGlassTabBar> createState() => _LiquidGlassTabBarState();
}

class _LiquidGlassTabBarState extends ConsumerState<LiquidGlassTabBar> {
  static const _viewType =
      'io.github.ktakada42.saitamagomicalendar/liquid_glass_tab_bar';

  static const _tabs = <_TabSpec>[
    _TabSpec(
      label: 'ホーム',
      icon: CupertinoIcons.house,
      selectedIcon: CupertinoIcons.house_fill,
    ),
    _TabSpec(
      label: 'カレンダー',
      icon: CupertinoIcons.calendar,
      selectedIcon: CupertinoIcons.calendar,
    ),
    _TabSpec(
      label: '分別',
      icon: CupertinoIcons.search,
      selectedIcon: CupertinoIcons.search,
    ),
    _TabSpec(
      label: '設定',
      icon: CupertinoIcons.gear,
      selectedIcon: CupertinoIcons.gear_solid,
    ),
  ];

  MethodChannel? _channel;
  Map<String, Object?>? _lastSentParams;

  Map<String, Object?> _buildParams({
    required Brightness brightness,
    required Color tintColor,
    required bool touchEnabled,
  }) {
    return <String, Object?>{
      'selectedIndex': widget.selectedIndex,
      'isDark': brightness == Brightness.dark,
      'tintColor': tintColor.toARGB32(),
      'touchEnabled': touchEnabled,
    };
  }

  void _attachChannel(int id, Map<String, Object?> initialParams) {
    final channel = MethodChannel('${_viewType}_$id');
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onSelect') {
        final index = call.arguments;
        if (index is int && mounted) {
          widget.onDestinationSelected(index);
        }
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
        prev['selectedIndex'] == next['selectedIndex'] &&
        prev['isDark'] == next['isDark'] &&
        prev['tintColor'] == next['tintColor'] &&
        prev['touchEnabled'] == next['touchEnabled']) {
      return;
    }
    _lastSentParams = next;
    unawaited(channel.invokeMethod<void>('update', next));
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highContrast = MediaQuery.highContrastOf(context);
    final useNative = ref.watch(nativeLiquidGlassViewProvider) && !highContrast;

    if (useNative) {
      final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
      // モーダルシートや別画面が上に重なっている間はネイティブ UITabBar の当たり判定を止め、
      // Flutter 側のバリアやシートへのタップを奪わないようにする。
      final isCurrentRoute = ModalRoute.of(context)?.isCurrent ?? true;
      final params = _buildParams(
        brightness: theme.brightness,
        tintColor: theme.colorScheme.primary,
        touchEnabled: isCurrentRoute,
      );
      _syncNativeParams(params);

      return SizedBox(
        height: 64 + bottomInset,
        child: UiKitView(
          viewType: _viewType,
          layoutDirection: TextDirection.ltr,
          creationParams: params,
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: (id) => _attachChannel(id, params),
        ),
      );
    }

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: SizedBox(
        height: 60,
        child: LiquidGlassSurface(
          shape: LiquidGlassShape.capsule,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            child: Row(
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  Expanded(
                    child: _FallbackTabItem(
                      spec: _tabs[i],
                      selected: i == widget.selectedIndex,
                      onTap: () => widget.onDestinationSelected(i),
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

class _FallbackTabItem extends StatelessWidget {
  const _FallbackTabItem({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  final _TabSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    final pillColor = selected
        ? theme.colorScheme.primary.withValues(alpha: 0.14)
        : Colors.transparent;

    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: pillColor,
            borderRadius: BorderRadius.circular(999),
            border: selected
                ? Border.all(color: theme.colorScheme.primary, width: 1.5)
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? spec.selectedIcon : spec.icon,
                size: 21,
                color: color,
              ),
              const SizedBox(height: 2),
              Text(
                spec.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
