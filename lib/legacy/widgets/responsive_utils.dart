import 'package:flutter/material.dart';

/// Common breakpoints and helpers for responsiveness.
class ResponsiveUtils {
  static const int mobileMax = 599;
  static const int tabletMax = 1023;

  static bool isMobile(BuildContext context) => MediaQuery.of(context).size.width <= mobileMax;
  static bool isTablet(BuildContext context) => MediaQuery.of(context).size.width > mobileMax && MediaQuery.of(context).size.width <= tabletMax;
  static bool isDesktop(BuildContext context) => MediaQuery.of(context).size.width > tabletMax;

  /// Returns a recommended horizontal padding based on screen width.
  static double horizontalPadding(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w > 1100) return 48.0;
    if (w > 800) return 32.0;
    return 16.0;
  }

  /// Returns the max content width to constrain forms/pages on large screens.
  static double maxContentWidth(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w > 1400) return 1200.0;
    if (w > 1100) return 1000.0;
    if (w > 800) return 800.0;
    return w;
  }
}

