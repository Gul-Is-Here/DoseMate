import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_palette.dart';

abstract class AppTheme {
  static final light = _build(AppPalette.light);
  static final dark = _build(AppPalette.dark);

  static ThemeData _build(AppPalette p) {
    final scheme = ColorScheme(
      brightness: p.brightness,
      primary: p.primary,
      onPrimary: p.onPrimary,
      primaryContainer: p.selected,
      onPrimaryContainer: p.onSelected,
      secondary: p.onSelected,
      onSecondary: p.card,
      secondaryContainer: p.selected,
      onSecondaryContainer: p.onSelected,
      tertiary: p.attention,
      onTertiary: p.card,
      tertiaryContainer: p.attentionContainer,
      onTertiaryContainer: p.attention,
      error: p.error,
      onError: p.onError,
      errorContainer: p.errorContainer,
      onErrorContainer: p.error,
      surface: p.card,
      onSurface: p.textPrimary,
      onSurfaceVariant: p.textSecondary,
      surfaceDim: p.background,
      surfaceBright: p.card,
      surfaceContainerLowest: p.card,
      surfaceContainerLow: p.card,
      surfaceContainer: p.elevated,
      surfaceContainerHigh: p.card,
      surfaceContainerHighest: p.elevated,
      outline: p.inputOutline,
      outlineVariant: p.divider,
      inverseSurface: p.inverseSurface,
      onInverseSurface: p.onInverseSurface,
      inversePrimary: p.isDark
          ? AppPalette.light.primary
          : AppPalette.dark.primary,
      shadow: Colors.black,
      scrim: Colors.black,
      // No tinted surfaces: cards stay neutral.
      surfaceTint: Colors.transparent,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(999),
    );
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: color, width: width),
        );
    final disabledFg = p.textPrimary.withValues(alpha: 0.38);
    final disabledBg = p.textPrimary.withValues(alpha: 0.12);
    return ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: scheme,
      extensions: [p],
      fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      cardColor: p.card,
      dividerColor: p.divider,
      disabledColor: disabledFg,
      hintColor: p.textSecondary,
      iconTheme: IconThemeData(color: p.textSecondary),
      dividerTheme: DividerThemeData(color: p.divider, space: 1),
      cardTheme: CardThemeData(color: p.card, elevation: 0),
      dialogTheme: DialogThemeData(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.card,
        modalBackgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: p.divider,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.card,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.inverseSurface,
        contentTextStyle: TextStyle(color: p.onInverseSurface),
        actionTextColor: p.isDark
            ? AppPalette.light.primary
            : AppPalette.dark.primary,
        behavior: SnackBarBehavior.floating,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(color: p.onInverseSurface),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.primary,
        linearTrackColor: p.divider,
        circularTrackColor: Colors.transparent,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.primary,
        selectionColor: p.primary.withValues(alpha: 0.3),
        selectionHandleColor: p.primary,
      ),
      // Only fallbacks: screens style their own fields. A plain field gets
      // an outline that turns indigo on focus and red on error.
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: TextStyle(color: p.textSecondary),
        labelStyle: TextStyle(color: p.textSecondary),
        floatingLabelStyle: TextStyle(color: p.primary),
        prefixIconColor: p.textSecondary,
        suffixIconColor: p.textSecondary,
        errorStyle: TextStyle(color: p.error),
        border: border(p.inputOutline),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? disabledBg : p.primary,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? disabledFg : p.onPrimary,
          ),
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          shape: WidgetStatePropertyAll(shape),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? disabledBg : p.primary,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? disabledFg : p.onPrimary,
          ),
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          shape: WidgetStatePropertyAll(shape),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? disabledFg : p.primary,
          ),
          side: WidgetStateProperty.resolveWith(
            (s) => BorderSide(
              color: s.contains(WidgetState.disabled)
                  ? p.divider
                  : s.contains(WidgetState.focused)
                  ? p.primary
                  : p.inputOutline,
            ),
          ),
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          shape: WidgetStatePropertyAll(shape),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? disabledFg : p.primary,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? disabledFg
              : s.contains(WidgetState.selected)
              ? p.onPrimary
              : p.inputOutline,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? disabledBg
              : s.contains(WidgetState.selected)
              ? p.primary
              : p.elevated,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Colors.transparent
              : p.inputOutline,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? disabledBg
              : s.contains(WidgetState.selected)
              ? p.primary
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(p.onPrimary),
        side: WidgetStateBorderSide.resolveWith(
          (s) => BorderSide(
            color: s.contains(WidgetState.disabled)
                ? disabledFg
                : s.contains(WidgetState.selected)
                ? p.primary
                : p.inputOutline,
            width: 2,
          ),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? disabledFg
              : s.contains(WidgetState.selected)
              ? p.primary
              : p.inputOutline,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.elevated,
        selectedColor: p.selected,
        disabledColor: disabledBg,
        labelStyle: TextStyle(color: p.textPrimary),
        secondaryLabelStyle: TextStyle(color: p.onSelected),
        checkmarkColor: p.onSelected,
        side: BorderSide.none,
        shape: shape,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? p.selected : p.card,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) =>
                s.contains(WidgetState.selected) ? p.onSelected : p.textPrimary,
          ),
          side: WidgetStatePropertyAll(BorderSide(color: p.divider)),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: p.selected,
        headerForegroundColor: p.onSelected,
        todayBorder: BorderSide(color: p.primary),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: p.card,
        dialBackgroundColor: p.elevated,
        hourMinuteColor: p.elevated,
        dayPeriodColor: p.selected,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.textSecondary,
        textColor: p.textPrimary,
        selectedColor: p.onSelected,
        selectedTileColor: p.selected,
      ),
    );
  }

  /// Tailwind `shadow-sm`.
  static const shadowSm = [
    BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1)),
  ];

  /// Tailwind `shadow-md`.
  static const shadowMd = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 6,
      spreadRadius: -1,
      offset: Offset(0, 4),
    ),
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 4,
      spreadRadius: -2,
      offset: Offset(0, 2),
    ),
  ];
}
