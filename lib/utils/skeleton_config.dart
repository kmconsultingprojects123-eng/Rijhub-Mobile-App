import 'package:flutter/material.dart';

/// Global configuration for AppSkeleton default colors.
///
/// Use `SkeletonConfig.setDefaultColors(...)` early in app startup
/// (for example in `main()` before runApp()) to apply brand colors.
class SkeletonConfig {
  SkeletonConfig._();

  static Color? _baseColor;
  static Color? _highlightColor;

  /// Set app-wide default colors for skeletons.
  /// If a color is null, AppSkeleton will fall back to theme-aware defaults.
  static void setDefaultColors({Color? baseColor, Color? highlightColor}) {
    _baseColor = baseColor;
    _highlightColor = highlightColor;
  }

  static Color? get baseColor => _baseColor;
  static Color? get highlightColor => _highlightColor;

  /// Clear previously set defaults.
  static void clear() {
    _baseColor = null;
    _highlightColor = null;
  }
}

