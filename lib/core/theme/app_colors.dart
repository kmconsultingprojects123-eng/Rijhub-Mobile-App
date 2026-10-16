import 'package:flutter/material.dart';

import 'palette.dart';

/// Semantic colours for RijHub, resolved for the current brightness.
///
/// Read them with `context.colors` (see `theme.dart`).
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.brand,
    required this.brandPressed,
    required this.brandStroke,
    required this.onBrand,
    required this.brandText,
    required this.brandSubtle,
    required this.brandSubtleBorder,
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceStrong,
    required this.onSurfaceStrong,
    required this.successOnStrong,
    required this.warningOnStrong,
    required this.border,
    required this.borderStrong,
    required this.inputBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.success,
    required this.successSubtle,
    required this.warning,
    required this.warningSubtle,
    required this.error,
    required this.errorSubtle,
    required this.info,
    required this.infoSubtle,
    required this.verified,
    required this.verifiedSubtle,
    required this.rating,
    required this.online,
    required this.scrim,
    required this.skeleton,
  });

  /// Filled primary actions and other crimson surfaces that carry
  /// [onBrand] content.
  final Color brand;
  final Color brandPressed;

  /// Thin crimson lines and small marks on the page: focus borders, carets,
  /// selected outlines, progress and ticks. Brighter than [brand] in dark
  /// mode, where the brand crimson is too dim for a hairline (2:1).
  final Color brandStroke;

  /// Text and icons placed on [brand].
  final Color onBrand;

  /// Brand-coloured text and icons on the page background (links, accents).
  final Color brandText;

  /// Tinted backgrounds for selected items and brand accents.
  final Color brandSubtle;
  final Color brandSubtleBorder;

  final Color background;
  final Color surface;

  /// Inputs, tiles and other quiet containers.
  final Color surfaceMuted;

  /// High-emphasis dark cards (for example earnings) and text on them.
  final Color surfaceStrong;
  final Color onSurfaceStrong;

  /// Status colours that stay readable on [surfaceStrong].
  final Color successOnStrong;
  final Color warningOnStrong;

  final Color border;
  final Color borderStrong;

  /// The edge of inputs and code boxes, 3:1 against the page so the field
  /// can be found at a glance.
  final Color inputBorder;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textDisabled;

  final Color success;
  final Color successSubtle;
  final Color warning;
  final Color warningSubtle;
  final Color error;
  final Color errorSubtle;

  /// Neutral, informative status ("On the way").
  final Color info;
  final Color infoSubtle;

  /// Identity-verified badge.
  final Color verified;
  final Color verifiedSubtle;

  /// Star ratings.
  final Color rating;

  /// "Available now" indicators.
  final Color online;

  final Color scrim;
  final Color skeleton;

  static const light = AppColors(
    brand: Palette.crimson600,
    brandPressed: Palette.crimson700,
    brandStroke: Palette.crimson600,
    onBrand: Palette.white,
    brandText: Palette.crimson600,
    brandSubtle: Palette.crimson50,
    brandSubtleBorder: Palette.crimson200,
    background: Palette.white,
    surface: Palette.white,
    surfaceMuted: Palette.neutral50,
    surfaceStrong: Palette.neutral900,
    onSurfaceStrong: Palette.white,
    successOnStrong: Color(0xFF4ADE80),
    warningOnStrong: Color(0xFFFBBF24),
    border: Palette.neutral200,
    borderStrong: Palette.neutral300,
    inputBorder: Palette.neutral450,
    textPrimary: Palette.neutral900,
    textSecondary: Palette.neutral600,
    textTertiary: Palette.neutral500,
    textDisabled: Palette.neutral400,
    success: Palette.green600,
    successSubtle: Palette.green50,
    warning: Palette.amber700,
    warningSubtle: Palette.amber50,
    error: Palette.red600,
    errorSubtle: Palette.red50,
    info: Palette.blue700,
    infoSubtle: Palette.blue50,
    verified: Palette.blue600,
    verifiedSubtle: Palette.blue50,
    rating: Palette.amber500,
    online: Palette.green500,
    scrim: Color(0x80000000),
    skeleton: Palette.neutral100,
  );

  static const dark = AppColors(
    brand: Palette.crimson600,
    brandPressed: Palette.crimson700,
    brandStroke: Palette.crimson400,
    onBrand: Palette.white,
    brandText: Palette.crimson300,
    brandSubtle: Color(0xFF260C13),
    brandSubtleBorder: Palette.crimson800,
    background: Palette.neutral950,
    surface: Color(0xFF161616),
    surfaceMuted: Color(0xFF1F1F1F),
    surfaceStrong: Color(0xFF232323),
    onSurfaceStrong: Palette.white,
    successOnStrong: Color(0xFF4ADE80),
    warningOnStrong: Color(0xFFFBBF24),
    border: Color(0xFF2A2A2A),
    borderStrong: Color(0xFF3A3A3A),
    inputBorder: Color(0xFF737373),
    textPrimary: Color(0xFFF5F5F5),
    textSecondary: Palette.neutral400,
    textTertiary: Color(0xFF8A8A8A),
    textDisabled: Color(0xFF5C5C5C),
    success: Color(0xFF4ADE80),
    successSubtle: Color(0xFF0F2A1A),
    warning: Color(0xFFFBBF24),
    warningSubtle: Color(0xFF2B1F08),
    error: Color(0xFFF97066),
    errorSubtle: Color(0xFF2D1110),
    info: Color(0xFF60A5FA),
    infoSubtle: Color(0xFF0F1D33),
    verified: Color(0xFF60A5FA),
    verifiedSubtle: Color(0xFF0F1D33),
    rating: Palette.amber500,
    online: Palette.green500,
    scrim: Color(0x99000000),
    skeleton: Color(0xFF232323),
  );

  @override
  AppColors copyWith({
    Color? brand,
    Color? brandPressed,
    Color? brandStroke,
    Color? onBrand,
    Color? brandText,
    Color? brandSubtle,
    Color? brandSubtleBorder,
    Color? background,
    Color? surface,
    Color? surfaceMuted,
    Color? surfaceStrong,
    Color? onSurfaceStrong,
    Color? successOnStrong,
    Color? warningOnStrong,
    Color? border,
    Color? borderStrong,
    Color? inputBorder,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textDisabled,
    Color? success,
    Color? successSubtle,
    Color? warning,
    Color? warningSubtle,
    Color? error,
    Color? errorSubtle,
    Color? info,
    Color? infoSubtle,
    Color? verified,
    Color? verifiedSubtle,
    Color? rating,
    Color? online,
    Color? scrim,
    Color? skeleton,
  }) {
    return AppColors(
      brand: brand ?? this.brand,
      brandPressed: brandPressed ?? this.brandPressed,
      brandStroke: brandStroke ?? this.brandStroke,
      onBrand: onBrand ?? this.onBrand,
      brandText: brandText ?? this.brandText,
      brandSubtle: brandSubtle ?? this.brandSubtle,
      brandSubtleBorder: brandSubtleBorder ?? this.brandSubtleBorder,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      surfaceStrong: surfaceStrong ?? this.surfaceStrong,
      onSurfaceStrong: onSurfaceStrong ?? this.onSurfaceStrong,
      successOnStrong: successOnStrong ?? this.successOnStrong,
      warningOnStrong: warningOnStrong ?? this.warningOnStrong,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      inputBorder: inputBorder ?? this.inputBorder,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textDisabled: textDisabled ?? this.textDisabled,
      success: success ?? this.success,
      successSubtle: successSubtle ?? this.successSubtle,
      warning: warning ?? this.warning,
      warningSubtle: warningSubtle ?? this.warningSubtle,
      error: error ?? this.error,
      errorSubtle: errorSubtle ?? this.errorSubtle,
      info: info ?? this.info,
      infoSubtle: infoSubtle ?? this.infoSubtle,
      verified: verified ?? this.verified,
      verifiedSubtle: verifiedSubtle ?? this.verifiedSubtle,
      rating: rating ?? this.rating,
      online: online ?? this.online,
      scrim: scrim ?? this.scrim,
      skeleton: skeleton ?? this.skeleton,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      brand: mix(brand, other.brand),
      brandPressed: mix(brandPressed, other.brandPressed),
      brandStroke: mix(brandStroke, other.brandStroke),
      onBrand: mix(onBrand, other.onBrand),
      brandText: mix(brandText, other.brandText),
      brandSubtle: mix(brandSubtle, other.brandSubtle),
      brandSubtleBorder: mix(brandSubtleBorder, other.brandSubtleBorder),
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      surfaceMuted: mix(surfaceMuted, other.surfaceMuted),
      surfaceStrong: mix(surfaceStrong, other.surfaceStrong),
      onSurfaceStrong: mix(onSurfaceStrong, other.onSurfaceStrong),
      successOnStrong: mix(successOnStrong, other.successOnStrong),
      warningOnStrong: mix(warningOnStrong, other.warningOnStrong),
      border: mix(border, other.border),
      borderStrong: mix(borderStrong, other.borderStrong),
      inputBorder: mix(inputBorder, other.inputBorder),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textTertiary: mix(textTertiary, other.textTertiary),
      textDisabled: mix(textDisabled, other.textDisabled),
      success: mix(success, other.success),
      successSubtle: mix(successSubtle, other.successSubtle),
      warning: mix(warning, other.warning),
      warningSubtle: mix(warningSubtle, other.warningSubtle),
      error: mix(error, other.error),
      errorSubtle: mix(errorSubtle, other.errorSubtle),
      info: mix(info, other.info),
      infoSubtle: mix(infoSubtle, other.infoSubtle),
      verified: mix(verified, other.verified),
      verifiedSubtle: mix(verifiedSubtle, other.verifiedSubtle),
      rating: mix(rating, other.rating),
      online: mix(online, other.online),
      scrim: mix(scrim, other.scrim),
      skeleton: mix(skeleton, other.skeleton),
    );
  }
}
