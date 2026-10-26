import 'package:flutter/material.dart';

/// DoseMate's colour tokens for one brightness.
///
/// Registered on both ThemeDatas as an extension, so widgets can read it
/// with `Theme.of(context).extension<AppPalette>()`. AppColors reads the
/// current palette, which ThemeController keeps in step with the theme.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.brightness,
    required this.primary,
    required this.onPrimary,
    required this.tertiary,
    required this.onTertiary,
    required this.background,
    required this.card,
    required this.elevated,
    required this.textPrimary,
    required this.textSecondary,
    required this.divider,
    required this.inputOutline,
    required this.selected,
    required this.onSelected,
    required this.shimmerBase,
    required this.shimmerHighlight,
    required this.success,
    required this.successContainer,
    required this.attention,
    required this.attentionContainer,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.neutral,
    required this.neutralContainer,
    required this.inverseSurface,
    required this.onInverseSurface,
  });

  final Brightness brightness;

  // Brand colors
  final Color primary;
  final Color onPrimary;
  final Color tertiary;
  final Color onTertiary;

  // Surfaces
  final Color background;
  final Color card;
  final Color elevated;

  // Text
  final Color textPrimary;
  final Color textSecondary;
  final Color divider;
  final Color inputOutline;

  // Selection
  final Color selected;
  final Color onSelected;

  // Loading shimmer
  final Color shimmerBase;
  final Color shimmerHighlight;

  // Dose statuses
  final Color success;
  final Color successContainer;
  final Color attention;
  final Color attentionContainer;
  final Color error;
  final Color onError;
  final Color errorContainer;
  final Color neutral;
  final Color neutralContainer;

  // Inverse surfaces
  final Color inverseSurface;
  final Color onInverseSurface;

  static const light = AppPalette(
    brightness: Brightness.light,

    // Primary: Lavender
    primary: Color(0xFF8B80D9),
    onPrimary: Color(0xFFFFFFFF),

    // Tertiary: Muted teal
    tertiary: Color(0xFF5BAA9B),
    onTertiary: Color(0xFF102D29),

    // Surfaces
    background: Color(0xFFF7F8FC),
    card: Color(0xFFFFFFFF),
    elevated: Color(0xFFEEF0F6),

    // Text
    textPrimary: Color(0xFF191B2A),
    textSecondary: Color(0xFF626579),

    // Borders and inputs
    divider: Color(0xFFE2E4EE),
    inputOutline: Color(0xFF797D93),

    // Selection
    selected: Color(0xFFEAE8FF),
    onSelected: Color(0xFF4338CA),

    // Loading shimmer
    shimmerBase: Color(0xFFE8EAF2),
    shimmerHighlight: Color(0xFFF5F6FA),

    // Success
    success: Color(0xFF18794E),
    successContainer: Color(0xFFE3F4EA),

    // Attention
    attention: Color(0xFF8A5700),
    attentionContainer: Color(0xFFFFF0D6),

    // Error
    error: Color(0xFFB42335),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFDE8EB),

    // Neutral
    neutral: Color(0xFF626579),
    neutralContainer: Color(0xFFEEF0F6),

    // Inverse surfaces
    inverseSurface: Color(0xFF2A2C3D),
    onInverseSurface: Color(0xFFF2F2FA),
  );

  static const dark = AppPalette(
    brightness: Brightness.dark,

    // Primary: Soft lavender
    primary: Color(0xFFB9B3FF),
    onPrimary: Color(0xFF211A60),

    // Tertiary: Light muted teal for dark surfaces
    tertiary: Color(0xFF83CFC0),
    onTertiary: Color(0xFF102D29),

    // Surfaces
    background: Color(0xFF111218),
    card: Color(0xFF1B1C25),
    elevated: Color(0xFF252633),

    // Text
    textPrimary: Color(0xFFF2F2FA),
    textSecondary: Color(0xFFB0B2C5),

    // Borders and inputs
    divider: Color(0xFF363847),
    inputOutline: Color(0xFF787C96),

    // Selection
    selected: Color(0xFF302B50),
    onSelected: Color(0xFFC7C2FF),

    // Loading shimmer
    shimmerBase: Color(0xFF252633),
    shimmerHighlight: Color(0xFF343647),

    // Success
    success: Color(0xFF75DBA7),
    successContainer: Color(0xFF17342A),

    // Attention
    attention: Color(0xFFF4C76B),
    attentionContainer: Color(0xFF3A2F14),

    // Error
    error: Color(0xFFFFABB5),
    onError: Color(0xFF4A0E17),
    errorContainer: Color(0xFF44202A),

    // Neutral
    neutral: Color(0xFFB0B2C5),
    neutralContainer: Color(0xFF252633),

    // Inverse surfaces
    inverseSurface: Color(0xFFE4E4F0),
    onInverseSurface: Color(0xFF191B2A),
  );

  /// The palette in use; set only by ThemeController and tests.
  static AppPalette current = light;

  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ?? current;

  bool get isDark => brightness == Brightness.dark;

  @override
  AppPalette copyWith({
    Brightness? brightness,
    Color? primary,
    Color? onPrimary,
    Color? tertiary,
    Color? onTertiary,
    Color? background,
    Color? card,
    Color? elevated,
    Color? textPrimary,
    Color? textSecondary,
    Color? divider,
    Color? inputOutline,
    Color? selected,
    Color? onSelected,
    Color? shimmerBase,
    Color? shimmerHighlight,
    Color? success,
    Color? successContainer,
    Color? attention,
    Color? attentionContainer,
    Color? error,
    Color? onError,
    Color? errorContainer,
    Color? neutral,
    Color? neutralContainer,
    Color? inverseSurface,
    Color? onInverseSurface,
  }) {
    return AppPalette(
      brightness: brightness ?? this.brightness,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      tertiary: tertiary ?? this.tertiary,
      onTertiary: onTertiary ?? this.onTertiary,
      background: background ?? this.background,
      card: card ?? this.card,
      elevated: elevated ?? this.elevated,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      divider: divider ?? this.divider,
      inputOutline: inputOutline ?? this.inputOutline,
      selected: selected ?? this.selected,
      onSelected: onSelected ?? this.onSelected,
      shimmerBase: shimmerBase ?? this.shimmerBase,
      shimmerHighlight: shimmerHighlight ?? this.shimmerHighlight,
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      attention: attention ?? this.attention,
      attentionContainer: attentionContainer ?? this.attentionContainer,
      error: error ?? this.error,
      onError: onError ?? this.onError,
      errorContainer: errorContainer ?? this.errorContainer,
      neutral: neutral ?? this.neutral,
      neutralContainer: neutralContainer ?? this.neutralContainer,
      inverseSurface: inverseSurface ?? this.inverseSurface,
      onInverseSurface: onInverseSurface ?? this.onInverseSurface,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;

    Color c(Color a, Color b) => Color.lerp(a, b, t)!;

    return AppPalette(
      brightness: t < 0.5 ? brightness : other.brightness,
      primary: c(primary, other.primary),
      onPrimary: c(onPrimary, other.onPrimary),
      tertiary: c(tertiary, other.tertiary),
      onTertiary: c(onTertiary, other.onTertiary),
      background: c(background, other.background),
      card: c(card, other.card),
      elevated: c(elevated, other.elevated),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      divider: c(divider, other.divider),
      inputOutline: c(inputOutline, other.inputOutline),
      selected: c(selected, other.selected),
      onSelected: c(onSelected, other.onSelected),
      shimmerBase: c(shimmerBase, other.shimmerBase),
      shimmerHighlight: c(shimmerHighlight, other.shimmerHighlight),
      success: c(success, other.success),
      successContainer: c(successContainer, other.successContainer),
      attention: c(attention, other.attention),
      attentionContainer: c(attentionContainer, other.attentionContainer),
      error: c(error, other.error),
      onError: c(onError, other.onError),
      errorContainer: c(errorContainer, other.errorContainer),
      neutral: c(neutral, other.neutral),
      neutralContainer: c(neutralContainer, other.neutralContainer),
      inverseSurface: c(inverseSurface, other.inverseSurface),
      onInverseSurface: c(onInverseSurface, other.onInverseSurface),
    );
  }
}
