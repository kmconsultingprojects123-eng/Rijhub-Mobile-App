import 'package:flutter/painting.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// The RijHub type scale. One family (Inter, bundled in assets/fonts/inter),
/// a small set of sizes, and tighter tracking as sizes grow. Sizes scale with
/// the screen through `.sp`, and the user's text-size setting applies on top.
///
/// Styles carry no colour; text inherits `textPrimary` from the theme. Add a
/// colour at the call site when a different one is needed:
/// `AppText.body.copyWith(color: context.colors.textSecondary)`.
abstract final class AppText {
  static const fontFamily = 'Inter';

  static TextStyle _style(
    double size,
    double lineHeight,
    FontWeight weight, [
    double tracking = 0,
  ]) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: size.sp,
        height: lineHeight / size,
        fontWeight: weight,
        letterSpacing: tracking.sp,
      );

  /// Hero headlines on onboarding screens. 32/38.
  static TextStyle get display => _style(30, 36, FontWeight.w700, -0.8);

  /// Screen titles. 26/32.
  static TextStyle get headline => _style(24, 30, FontWeight.w700, -0.5);

  /// Section titles and large numbers. 20/26.
  static TextStyle get title => _style(18, 24, FontWeight.w700, -0.3);

  /// Card and list-item titles. 16/22.
  static TextStyle get titleSmall => _style(15, 20, FontWeight.w600, -0.15);

  /// Lead paragraphs. 16/24.
  static TextStyle get bodyLarge => _style(16, 24, FontWeight.w400, -0.1);

  /// Default body text. 15/22.
  static TextStyle get body => _style(15, 22, FontWeight.w400, -0.05);

  /// Supporting text. 13/18.
  static TextStyle get bodySmall => _style(13, 18, FontWeight.w400);

  /// Button labels. 16/20.
  static TextStyle get label => _style(16, 20, FontWeight.w600, -0.1);

  /// Small labels, links and chips. 14/18.
  static TextStyle get labelSmall => _style(14, 18, FontWeight.w600, -0.05);

  /// Metadata, tab labels and tags. 12/16.
  static TextStyle get caption => _style(12, 16, FontWeight.w500);
}
