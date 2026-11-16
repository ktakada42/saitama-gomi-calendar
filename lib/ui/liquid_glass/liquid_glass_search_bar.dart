import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:material_ui/material_ui.dart';

import 'liquid_glass_surface.dart';

/// iOS 26 以降の分別早見表などで使うカプセル型の Liquid Glass 検索欄。
class LiquidGlassSearchBar extends StatelessWidget {
  const LiquidGlassSearchBar({
    super.key,
    required this.controller,
    required this.hintText,
    required this.showClear,
    required this.onClear,
    this.focusNode,
    this.onTap,
    this.onChanged,
    this.onSubmitted,
    this.clearTooltip = '入力を消す',
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final bool showClear;
  final VoidCallback onClear;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String clearTooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = theme.colorScheme.onSurfaceVariant;

    return SizedBox(
      height: 46,
      child: LiquidGlassSurface(
        shape: LiquidGlassShape.capsule,
        interactive: true,
        child: Center(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            textInputAction: TextInputAction.search,
            textAlignVertical: TextAlignVertical.center,
            onTap: onTap,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            decoration: InputDecoration(
              hintText: hintText,
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 11),
              prefixIcon: Icon(
                CupertinoIcons.search,
                size: 19,
                color: iconColor,
              ),
              suffixIcon: !showClear
                  ? null
                  : IconButton(
                      tooltip: clearTooltip,
                      icon: Icon(
                        CupertinoIcons.xmark_circle_fill,
                        size: 18,
                        color: iconColor,
                      ),
                      onPressed: onClear,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
