import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'pressable.dart';

/// A round icon button with a 48-point tap area and an optional unread dot.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.filled = false,
    this.showBadge = false,
    this.iconColor,
    this.backgroundColor,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String semanticLabel;

  /// Sits on a muted circle instead of the bare page.
  final bool filled;
  final bool showBadge;
  final Color? iconColor;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onTap: onPressed,
      semanticLabel: showBadge ? '$semanticLabel, new' : semanticLabel,
      pressedScale: 0.92,
      focusRadius: AppRadius.pillAll,
      // The 48pt touch area already rings the 44pt circle.
      focusOffset: 0,
      child: SizedBox.square(
        dimension: AppSize.minTapTarget,
        child: Center(
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: backgroundColor ??
                  (filled ? c.surfaceMuted : Colors.transparent),
              shape: BoxShape.circle,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  icon,
                  size: AppSize.icon,
                  color: iconColor ??
                      (onPressed == null ? c.textDisabled : c.textPrimary),
                ),
                if (showBadge)
                  Positioned(
                    top: 10,
                    right: 11,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: c.brandStroke,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: backgroundColor ??
                              (filled ? c.surfaceMuted : c.background),
                          width: 1.5,
                        ),
                      ),
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
