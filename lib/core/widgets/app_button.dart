import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/palette.dart';
import '../theme/theme.dart';

enum AppButtonVariant {
  /// The one main action on a screen. Brand crimson.
  primary,

  /// Alternative actions. Outlined, neutral.
  secondary,

  /// Low-emphasis actions such as "Skip". Text only.
  tertiary,

  /// A white button for use on crimson, dark or photo backgrounds.
  inverse,
}

enum AppButtonSize {
  /// 56 tall. Screen-level actions.
  large,

  /// 48 tall.
  medium,

  /// Looks 36 tall; its touch area is still 48.
  small,
}

/// The RijHub button. Use one primary button per screen.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.large,
    this.leading,
    this.trailing,
    this.isLoading = false,
    this.expand = true,
    this.semanticLabel,
  });

  final String label;

  /// Null disables the button.
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final Widget? leading;
  final Widget? trailing;

  /// Shows a spinner and ignores taps, keeping the button's size.
  final bool isLoading;

  /// Fill the available width.
  final bool expand;

  /// What a screen reader says instead of [label], for buttons that repeat
  /// down a list ("Send quote for AC repair in Garki").
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    final (Color bg, Color bgPressed, Color fg, Color? border) =
        switch (variant) {
      AppButtonVariant.primary => (c.brand, c.brandPressed, c.onBrand, null),
      AppButtonVariant.secondary => (
          c.surface,
          c.surfaceMuted,
          c.textPrimary,
          c.borderStrong
        ),
      AppButtonVariant.tertiary => (
          Colors.transparent,
          c.brandSubtle,
          c.brandText,
          null
        ),
      AppButtonVariant.inverse => (
          Colors.white,
          const Color(0xFFF1F1F1),
          Palette.crimson600,
          null
        ),
    };
    // Inverse buttons sit on crimson or dark cards, so their disabled state
    // is a translucent white that reads on both.
    final (Color disabledBg, Color disabledFg) = switch (variant) {
      AppButtonVariant.tertiary => (Colors.transparent, c.textDisabled),
      AppButtonVariant.inverse => (
          Colors.white.withValues(alpha: 0.16),
          Colors.white.withValues(alpha: 0.5),
        ),
      _ => (c.border, c.textDisabled),
    };

    // Keyboard focus draws a ring just outside the button: white around a
    // white button, the text colour around the rest.
    final focusRing = BorderSide(
      color: variant == AppButtonVariant.inverse ? Colors.white : c.textPrimary,
      width: 2,
      strokeAlign: BorderSide.strokeAlignOutside,
    );

    final (double height, double padding, TextStyle textStyle) = switch (size) {
      AppButtonSize.large => (AppSize.buttonLarge, 24.0, AppText.label),
      AppButtonSize.medium => (AppSize.buttonMedium, 20.0, AppText.label),
      AppButtonSize.small => (AppSize.buttonSmall, 14.0, AppText.labelSmall),
    };
    final isSmall = size == AppButtonSize.small;

    final style = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return disabledBg;
        if (states.contains(WidgetState.pressed)) return bgPressed;
        return bg;
      }),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled) ? disabledFg : fg,
      ),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      side: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.focused)) return focusRing;
        if (border == null) return null;
        return BorderSide(
          color: states.contains(WidgetState.disabled) ? c.border : border,
        );
      }),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      ),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: padding),
      ),
      minimumSize: WidgetStatePropertyAll(Size(0, height)),
      // Small buttons keep their 36pt look but get Material's padded 48pt
      // touch area; the larger sizes already meet it.
      tapTargetSize: isSmall
          ? MaterialTapTargetSize.padded
          : MaterialTapTargetSize.shrinkWrap,
      elevation: const WidgetStatePropertyAll(0),
      textStyle: WidgetStatePropertyAll(textStyle),
      splashFactory: NoSplash.splashFactory,
      animationDuration: context.motion(AppMotion.fast),
    );

    final labelRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 10)],
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );

    final Widget content = isLoading
        ? Stack(
            alignment: Alignment.center,
            children: [
              // Holds the button at its label's width while loading.
              Opacity(opacity: 0, child: labelRow),
              SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation(fg),
                ),
              ),
            ],
          )
        : labelRow;

    VoidCallback? handler;
    if (onPressed != null) {
      handler = isLoading
          ? () {}
          : () {
              if (variant == AppButtonVariant.primary) {
                HapticFeedback.selectionClick();
              }
              onPressed!();
            };
    }

    Widget button =
        TextButton(onPressed: handler, style: style, child: content);
    if (!isSmall) {
      button = SizedBox(
        width: expand ? double.infinity : null,
        height: height,
        child: button,
      );
    } else if (expand) {
      button = SizedBox(width: double.infinity, child: button);
    }

    // One node whatever the state, so a screen reader keeps its place on
    // the button when it starts loading; only what it says changes.
    final spoken = semanticLabel ?? label;
    return Semantics(
      container: true,
      button: true,
      enabled: onPressed != null,
      label: isLoading ? '$spoken, loading' : spoken,
      // Excluding the child drops its tap action, so restore it here.
      onTap: handler,
      excludeSemantics: true,
      child: button,
    );
  }
}
