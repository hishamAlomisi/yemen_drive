import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_palette.dart';

abstract final class AppTheme {
  static ThemeData get light => lightFor();

  static ThemeData lightFor({
    AppPalette palette = AppPalette.olive,
  }) =>
      _build(
        brightness: Brightness.light,
        palette: palette,
        background: palette.colors.lightBackground ?? AppColors.lightBackground,
        surface: palette.colors.lightSurface ?? AppColors.lightSurface,
        surfaceAlt: palette.colors.lightSurfaceAlt ?? AppColors.lightSurfaceAlt,
        onSurface: palette.colors.lightText ?? AppColors.lightText,
        muted: palette.colors.lightMuted ?? AppColors.lightMuted,
      );

  static ThemeData get dark => darkFor();

  static ThemeData darkFor({
    AppPalette palette = AppPalette.olive,
  }) =>
      _build(
        brightness: Brightness.dark,
        palette: palette,
        background: palette.colors.darkBackground ?? AppColors.darkBackground,
        surface: palette.colors.darkSurface ?? AppColors.darkSurface,
        surfaceAlt: palette.colors.darkSurfaceAlt ?? AppColors.darkSurfaceAlt,
        onSurface: palette.colors.darkText ?? AppColors.darkText,
        muted: palette.colors.darkMuted ?? AppColors.darkMuted,
      );

  static ThemeData _build({
    required Brightness brightness,
    required AppPalette palette,
    required Color background,
    required Color surface,
    required Color surfaceAlt,
    required Color onSurface,
    required Color muted,
  }) {
    final colors = palette.colors;
    final isDark = brightness == Brightness.dark;
    final primary =
        isDark ? colors.darkPrimary ?? colors.primary : colors.primary;
    final primaryDark = isDark
        ? colors.darkPrimaryDark ?? colors.primaryDark
        : colors.primaryDark;
    final secondary =
        isDark ? colors.darkSecondary ?? colors.secondary : colors.secondary;
    final border = colors.border ?? onSurface.withValues(alpha: .16);
    final onPrimary = (isDark ? colors.darkOnPrimary : colors.onPrimary) ??
        AppColors.onColor(primary);
    final onSecondary = palette == AppPalette.olive && isDark
        ? colors.darkBackground!
        : AppColors.onColor(secondary);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      secondary: secondary,
      onSecondary: onSecondary,
      surface: surface,
      error: AppColors.error,
    ).copyWith(
      primaryContainer: palette == AppPalette.olive ? surfaceAlt : null,
      secondaryContainer: palette == AppPalette.olive ? surfaceAlt : null,
      onSecondaryContainer: palette == AppPalette.olive ? onSurface : null,
      onPrimaryContainer: isDark ? primary : primaryDark,
      onSurface: onSurface,
      onSurfaceVariant: muted,
      surfaceContainer: surfaceAlt,
      surfaceContainerLowest: palette == AppPalette.olive ? surface : null,
      surfaceContainerLow: palette == AppPalette.olive ? surfaceAlt : null,
      surfaceContainerHigh: surfaceAlt,
      surfaceContainerHighest: surfaceAlt,
      outline: border,
      onError: AppColors.onColor(AppColors.error),
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      fontFamily: 'NotoSansArabic',
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
        headlineLarge: textTheme.headlineLarge
            ?.copyWith(fontSize: 30, fontWeight: FontWeight.w700, height: 1.35),
        headlineMedium: textTheme.headlineMedium
            ?.copyWith(fontSize: 26, fontWeight: FontWeight.w700, height: 1.35),
        headlineSmall: textTheme.headlineSmall
            ?.copyWith(fontSize: 22, fontWeight: FontWeight.w600, height: 1.4),
        titleLarge: textTheme.titleLarge
            ?.copyWith(fontSize: 20, fontWeight: FontWeight.w600, height: 1.4),
        titleMedium: textTheme.titleMedium
            ?.copyWith(fontSize: 16, fontWeight: FontWeight.w600, height: 1.45),
        titleSmall: textTheme.titleSmall
            ?.copyWith(fontSize: 14, fontWeight: FontWeight.w500, height: 1.45),
        bodyLarge: textTheme.bodyLarge
            ?.copyWith(fontSize: 16, fontWeight: FontWeight.w400, height: 1.5),
        bodyMedium: textTheme.bodyMedium
            ?.copyWith(fontSize: 14, fontWeight: FontWeight.w400, height: 1.5),
        bodySmall: textTheme.bodySmall
            ?.copyWith(fontSize: 12, color: muted, height: 1.4),
        labelLarge: textTheme.labelLarge
            ?.copyWith(fontSize: 16, fontWeight: FontWeight.w500),
        labelMedium: textTheme.labelMedium
            ?.copyWith(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
        backgroundColor: surface,
        foregroundColor: onSurface,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        prefixIconColor: muted,
        suffixIconColor: muted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.error),
        ),
      ),
      dividerColor: colors.border == null
          ? onSurface.withValues(alpha: .10)
          : border.withValues(alpha: .55),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface.withValues(alpha: .94),
        contentTextStyle: TextStyle(color: onSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: primary,
        indicatorShape: const StadiumBorder(),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? onPrimary
                : onSurface.withValues(alpha: .72),
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? primary
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
          side: BorderSide(
            color: colors.border == null
                ? onSurface.withValues(alpha: .08)
                : border.withValues(alpha: .72),
          ),
        ),
      ),
      iconTheme: IconThemeData(color: onSurface),
      primaryIconTheme: IconThemeData(color: onPrimary),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: onSurface),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
            foregroundColor:
                brightness == Brightness.light ? primaryDark : primary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: isDark ? primary : primaryDark,
          side: BorderSide(color: primary),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: onPrimary,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: onSurface,
        textColor: onSurface,
      ),
    );
  }
}
