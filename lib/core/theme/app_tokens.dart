import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Screens are designed on a 390 x 844 frame and scale with the device
/// through flutter_screenutil: `.w` for spacing, sizes and corner radii
/// (radii follow the spacing so corners keep their look on short phones),
/// `.sp` for type. `RijHubApp` caps the scale at 125% so tablets don't
/// balloon. Tokens read the scale when used, so they are getters.

/// Spacing on a 4-point grid. Screens use [gutter] for their side padding.
abstract final class AppSpace {
  static double get s2 => 2.w;
  static double get s4 => 4.w;
  static double get s6 => 6.w;
  static double get s8 => 8.w;
  static double get s12 => 12.w;
  static double get s16 => 16.w;
  static double get s20 => 20.w;
  static double get s24 => 24.w;
  static double get s28 => 28.w;
  static double get s32 => 32.w;
  static double get s40 => 40.w;
  static double get s48 => 48.w;
  static double get s64 => 64.w;

  /// Horizontal padding for every screen.
  static double get gutter => 20.w;
}

/// Corner radii.
abstract final class AppRadius {
  /// Small blocks, such as skeleton lines.
  static double get sm => 8.w;

  /// Buttons, inputs and icon tiles.
  static double get md => 12.w;

  /// Cards.
  static double get lg => 16.w;

  /// Sheets and hero panels.
  static double get xl => 28.w;

  /// Chips, tags and badges.
  static const pill = 999.0;

  static BorderRadius get smAll => BorderRadius.circular(sm);
  static BorderRadius get mdAll => BorderRadius.circular(md);
  static BorderRadius get lgAll => BorderRadius.circular(lg);
  static BorderRadius get xlAll => BorderRadius.circular(xl);
  static const pillAll = BorderRadius.all(Radius.circular(pill));
}

/// Standard control heights and icon sizes.
abstract final class AppSize {
  /// The smallest tap target allowed. Never scaled down.
  static const minTapTarget = 48.0;

  static double get buttonLarge => math.max(48, 52.w);
  static double get buttonMedium => math.max(minTapTarget, 48.w);

  /// Visual height only; small buttons pad their touch area to 48.
  static double get buttonSmall => 36.w;
  static double get input => math.max(48, 52.w);
  static double get iconSmall => 16.w;
  static double get icon => 22.w;
  static double get iconLarge => 26.w;
}

/// Durations and curves. Motion is quick and quiet: it explains a change,
/// it never decorates.
abstract final class AppMotion {
  static const fast = Duration(milliseconds: 150);
  static const base = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 400);

  static const Curve standard = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
}

/// For the rare surface that floats over content without a scrim, such as
/// a menu. Cards and bars use a border, and sheets sit on a scrim.
abstract final class AppShadows {
  static const floating = [
    BoxShadow(color: Color(0x14000000), blurRadius: 24, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1)),
  ];
}
