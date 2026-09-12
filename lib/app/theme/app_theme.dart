import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_palette.dart';

abstract final class AppTheme {
  static ThemeData get light => lightFor();

  static ThemeData lightFor({
    AppPalette palette = AppPalette.blueGold,
  }) =>
      _build(
        brightness: Brightness.light,
        palette: palette,
        background: AppColors.lightBackground,
        surface: AppColors.lightSurface,
        onSurface: AppColors.lightText,
        muted: AppColors.lightMuted,
      );

  static ThemeData get dark => darkFor();

  static ThemeData darkFor({
    AppPalette palette = AppPalette.blueGold,
  }) =>
      _build(
        brightness: Brightness.dark,
        palette: palette,
        background: AppColors.darkBackground,
        surface: AppColors.darkSurface,
        onSurface: AppColors.darkText,
        muted: AppColors.darkMuted,
      );

  static ThemeData _build({
    required Brightness brightness,
    required AppPalette palette,
    required Color background,
    required Color surface,
    required Color onSurface,
    required Color muted,
  }) {
    final colors = palette.colors;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: colors.primary,
      brightness: brightness,
      primary: colors.primary,
      onPrimary: Colors.white,
      secondary: colors.secondary,
      surface: surface,
      error: AppColors.error,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      fontFamily: 'BeINArabic',
      fontFamilyFallback: const <String>[
        'Tajawal',
        'Cairo',
        'Noto Sans Arabic',
        'Arial',
      ],
    );
    final textTheme = base.textTheme.apply(
      bodyColor: onSurface,
      displayColor: onSurface,
    );
    return base.copyWith(
      textTheme: textTheme.copyWith(
        headlineLarge: textTheme.headlineLarge?.copyWith(
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
        headlineSmall: textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
        titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        bodyLarge: textTheme.bodyLarge?.copyWith(height: 1.5),
        bodyMedium: textTheme.bodyMedium?.copyWith(height: 1.5),
        bodySmall: textTheme.bodySmall?.copyWith(color: muted, height: 1.45),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: onSurface,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: onSurface.withValues(alpha: .16)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: onSurface.withValues(alpha: .16)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.error),
        ),
      ),
      dividerColor: onSurface.withValues(alpha: .10),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface.withValues(alpha: .94),
        contentTextStyle: TextStyle(color: onSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: colors.primary,
        indicatorShape: const StadiumBorder(),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? Colors.white
                : onSurface.withValues(alpha: .72),
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? colors.primary
                : onSurface.withValues(alpha: .72),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: onSurface.withValues(alpha: .08)),
        ),
      ),
    );
  }
}
