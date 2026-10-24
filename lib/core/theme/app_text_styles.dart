import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Plus Jakarta Sans type scale from the design system (size / line height).
abstract class AppTextStyles {
  static TextStyle _base(
    double size,
    double lineHeight,
    FontWeight weight, [
    double letterSpacingEm = 0,
  ]) => GoogleFonts.plusJakartaSans(
    fontSize: size,
    height: lineHeight / size,
    fontWeight: weight,
    letterSpacing: letterSpacingEm * size,
  );

  static final headlineLgMobile = _base(24, 32, FontWeight.w700);
  static final titleLg = _base(20, 26, FontWeight.w600);
  static final titleMd = _base(18, 24, FontWeight.w600);
  static final bodyLg = _base(18, 28, FontWeight.w400);
  static final bodyMd = _base(16, 24, FontWeight.w400);
  static final bodySm = _base(14, 20, FontWeight.w500);
  static final labelLg = _base(16, 22, FontWeight.w600, 0.01);
  static final labelMd = _base(14, 18, FontWeight.w600, 0.02);
  static final labelSm = _base(12, 16, FontWeight.w700, 0.03);
}

extension AppTextStyleWeight on TextStyle {
  /// Changes the weight and loads the matching font file; a plain
  /// `copyWith(fontWeight:)` keeps the original weight's file.
  TextStyle weight(FontWeight weight) =>
      GoogleFonts.plusJakartaSans(textStyle: copyWith(fontWeight: weight));
}
