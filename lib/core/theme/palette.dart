import 'package:flutter/painting.dart';

/// Raw colour values for the RijHub design system.
///
/// Widgets should not use these directly. Read semantic colours from the
/// theme instead (`context.colors`), so light and dark mode stay correct.
abstract final class Palette {
  // Brand crimson, taken from the RijHub logo (#A20025).
  static const crimson50 = Color(0xFFFCF2F4);
  static const crimson100 = Color(0xFFF9E3E8);
  static const crimson200 = Color(0xFFF2C4CE);
  static const crimson300 = Color(0xFFE595A6);
  static const crimson400 = Color(0xFFD25A75);
  static const crimson500 = Color(0xFFBB1C43);
  static const crimson600 = Color(0xFFA20025);
  static const crimson700 = Color(0xFF87001F);
  static const crimson800 = Color(0xFF6C0019);
  static const crimson900 = Color(0xFF520013);

  // Neutrals, from the logo's black to white.
  static const white = Color(0xFFFFFFFF);
  static const neutral50 = Color(0xFFF7F7F7);
  static const neutral100 = Color(0xFFF0F0F0);
  static const neutral200 = Color(0xFFE5E5E5);
  static const neutral300 = Color(0xFFD4D4D4);
  static const neutral400 = Color(0xFFA3A3A3);
  static const neutral450 = Color(0xFF8A8A8A);
  static const neutral500 = Color(0xFF6B6B6B);
  static const neutral600 = Color(0xFF525252);
  static const neutral700 = Color(0xFF404040);
  static const neutral800 = Color(0xFF262626);
  static const neutral850 = Color(0xFF1C1C1C);
  static const neutral900 = Color(0xFF171717);
  static const neutral950 = Color(0xFF0D0D0D);

  // Status colours.
  static const green500 = Color(0xFF16A34A);
  static const green600 = Color(0xFF15803D);
  static const green50 = Color(0xFFEDF8F1);
  static const amber500 = Color(0xFFF5A524);
  static const amber700 = Color(0xFFA15C07);
  static const amber50 = Color(0xFFFFF6E8);
  static const red600 = Color(0xFFD92D20);
  static const red50 = Color(0xFFFEF1F0);
  static const blue600 = Color(0xFF1F6FEB);
  static const blue700 = Color(0xFF1D63D6);
  static const blue50 = Color(0xFFEDF4FF);
}
