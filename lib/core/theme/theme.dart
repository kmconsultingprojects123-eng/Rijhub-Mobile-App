import 'package:flutter/material.dart';

import 'app_colors.dart';

export 'app_colors.dart';
export 'app_theme.dart';
export 'app_tokens.dart';
export 'app_typography.dart';

extension AppThemeContext on BuildContext {
  /// Semantic colours for the current brightness.
  AppColors get colors => Theme.of(this).extension<AppColors>()!;

  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  /// [duration], or none when the person has turned on reduced motion.
  Duration motion(Duration duration) =>
      MediaQuery.disableAnimationsOf(this) ? Duration.zero : duration;
}
