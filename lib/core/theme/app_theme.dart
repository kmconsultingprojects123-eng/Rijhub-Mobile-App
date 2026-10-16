import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_tokens.dart';
import 'app_typography.dart';

/// Builds the Material theme from RijHub's tokens.
///
/// Our own components read [AppColors] directly; this mapping keeps stock
/// Material widgets (dialogs, sheets, switches, snackbars) consistent too.
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light, AppColors.light);
  static ThemeData dark() => _build(Brightness.dark, AppColors.dark);

  static ThemeData _build(Brightness brightness, AppColors c) {
    final isDark = brightness == Brightness.dark;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.brand,
      onPrimary: c.onBrand,
      primaryContainer: c.brandSubtle,
      onPrimaryContainer: c.brandText,
      secondary: c.brand,
      onSecondary: c.onBrand,
      error: c.error,
      onError: c.onBrand,
      surface: c.surface,
      onSurface: c.textPrimary,
      onSurfaceVariant: c.textSecondary,
      surfaceTint: Colors.transparent,
      surfaceContainerLowest: c.background,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.surface,
      surfaceContainerHighest: c.surfaceMuted,
      outline: c.borderStrong,
      outlineVariant: c.border,
      shadow: Colors.black,
      scrim: c.scrim,
      inverseSurface: c.surfaceStrong,
      onInverseSurface: c.onSurfaceStrong,
    );

    final textTheme = TextTheme(
      displaySmall: AppText.display,
      headlineSmall: AppText.headline,
      titleLarge: AppText.title,
      titleMedium: AppText.titleSmall,
      titleSmall: AppText.labelSmall,
      bodyLarge: AppText.bodyLarge,
      bodyMedium: AppText.body,
      bodySmall: AppText.bodySmall.copyWith(color: c.textSecondary),
      labelLarge: AppText.label,
      labelMedium: AppText.labelSmall,
      labelSmall: AppText.caption,
    ).apply(bodyColor: c.textPrimary, displayColor: c.textPrimary);

    OutlineInputBorder inputBorder(Color color, double width) =>
        OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: AppText.fontFamily,
      textTheme: textTheme,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      dividerColor: c.border,
      splashFactory: NoSplash.splashFactory,
      highlightColor: c.textPrimary.withValues(alpha: 0.04),
      hoverColor: c.textPrimary.withValues(alpha: 0.04),
      iconTheme: IconThemeData(color: c.textPrimary, size: AppSize.icon),
      extensions: [c],
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.brandStroke,
        selectionColor: c.brandStroke.withValues(alpha: 0.22),
        selectionHandleColor: c.brandStroke,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: AppText.titleSmall.copyWith(color: c.textPrimary),
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceMuted,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSpace.s16,
          vertical: AppSpace.s16,
        ),
        hintStyle: AppText.bodyLarge.copyWith(color: c.textTertiary),
        errorStyle: AppText.caption.copyWith(color: c.error),
        border: inputBorder(c.inputBorder, 1),
        enabledBorder: inputBorder(c.inputBorder, 1),
        disabledBorder: inputBorder(c.border, 1),
        focusedBorder: inputBorder(c.brandStroke, 1.5),
        errorBorder: inputBorder(c.error, 1),
        focusedErrorBorder: inputBorder(c.error, 1.5),
      ),
      dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.brandStroke,
        linearTrackColor: c.border,
        circularTrackColor: Colors.transparent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? c.success
              : c.borderStrong,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: c.borderStrong,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
        titleTextStyle: AppText.title.copyWith(color: c.textPrimary),
        contentTextStyle: AppText.body.copyWith(color: c.textSecondary),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.surfaceStrong,
        contentTextStyle: AppText.body.copyWith(color: c.onSurfaceStrong),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
