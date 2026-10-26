import 'package:flutter/material.dart';

import 'app_palette.dart';

/// The app's colour roles, resolved from the active [AppPalette] (light or
/// dark). These are getters, not constants: the theme can change while
/// the app runs, and [ThemeController] rebuilds the tree when it does.
///
/// The Material-style names below are the ones the screens were built
/// with; each maps onto one semantic token.
abstract class AppColors {
  static AppPalette get _p => AppPalette.current;

  // Semantic tokens.

  static Color get background => _p.background;
  static Color get card => _p.card;
  static Color get elevated => _p.elevated;
  static Color get textPrimary => _p.textPrimary;
  static Color get textSecondary => _p.textSecondary;
  static Color get divider => _p.divider;
  static Color get inputOutline => _p.inputOutline;
  static Color get selected => _p.selected;
  static Color get onSelected => _p.onSelected;

  /// Taken / success.
  static Color get success => _p.success;
  static Color get successContainer => _p.successContainer;

  /// Due / attention: low supply, coming up, appointments.
  static Color get attention => _p.attention;
  static Color get attentionContainer => _p.attentionContainer;

  /// Overdue / error and destructive actions.
  static Color get error => _p.error;
  static Color get onError => _p.onError;
  static Color get errorContainer => _p.errorContainer;

  /// Skipped / neutral.
  static Color get neutral => _p.neutral;
  static Color get neutralContainer => _p.neutralContainer;

  /// Soft drop shadows: barely there on dark surfaces.
  static Color get shadow =>
      _p.isDark ? const Color(0x66000000) : const Color(0x14191B2A);

  // Material-style roles.

  static Color get primary => _p.primary;
  static Color get onPrimary => _p.onPrimary;

  /// Solid accents (active strips, the main floating button): indigo.
  static Color get primaryContainer => _p.primary;
  static Color get onPrimaryContainer => _p.onPrimary;

  /// Selected and highlighted backgrounds.
  static Color get primaryFixed => _p.selected;
  static Color get primaryFixedDim => _p.selected;
  static Color get onPrimaryFixed => _p.onSelected;
  static Color get onPrimaryFixedVariant => _p.onSelected;

  /// Attention accents (low supply, appointments, overdue strips).
  static Color get secondary => _p.attention;
  static Color get secondaryContainer => _p.attention;
  static Color get onSecondaryContainer => _p.attentionContainer;
  static Color get secondaryFixed => _p.attentionContainer;
  static Color get onSecondaryFixed => _p.attention;
  static Color get onSecondaryFixedVariant => _p.attention;

  static Color get surface => _p.background;
  static Color get surfaceContainerLowest => _p.card;
  static Color get surfaceContainerLow => _p.elevated;
  static Color get surfaceContainer => _p.elevated;
  static Color get surfaceContainerHigh => _p.divider;
  static Color get surfaceContainerHighest => _p.divider;

  static Color get onSurface => _p.textPrimary;
  static Color get onBackground => _p.textPrimary;
  static Color get onSurfaceVariant => _p.textSecondary;
  static Color get outline => _p.inputOutline;
  static Color get outlineVariant => _p.divider;

  static Color get inverseSurface => _p.inverseSurface;
  static Color get inverseOnSurface => _p.onInverseSurface;
  static Color get inversePrimary =>
      _p.isDark ? AppPalette.light.primary : AppPalette.dark.primary;
}
