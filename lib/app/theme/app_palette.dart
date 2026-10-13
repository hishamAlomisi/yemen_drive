import 'package:flutter/material.dart';

enum AppPalette { yemenDrive, blueGold, midnightBurgundy, modern }

extension AppPaletteLabels on AppPalette {
  String get label => switch (this) {
        AppPalette.yemenDrive => 'يمن درايف',
        AppPalette.blueGold => 'الهوية الزرقاء الذهبية',
        AppPalette.midnightBurgundy => 'العنابي الليلي',
        AppPalette.modern => 'ثيم مودرن',
      };
}

@immutable
class AppPaletteColors {
  const AppPaletteColors({
    required this.primary,
    required this.primaryDark,
    required this.secondary,
    this.lightBackground,
    this.lightSurface,
    this.lightSurfaceAlt,
    this.lightText,
    this.lightMuted,
    this.darkBackground,
    this.darkSurface,
    this.darkSurfaceAlt,
    this.darkText,
    this.darkMuted,
    this.border,
  });

  final Color primary;
  final Color primaryDark;
  final Color secondary;
  final Color? lightBackground;
  final Color? lightSurface;
  final Color? lightSurfaceAlt;
  final Color? lightText;
  final Color? lightMuted;
  final Color? darkBackground;
  final Color? darkSurface;
  final Color? darkSurfaceAlt;
  final Color? darkText;
  final Color? darkMuted;
  final Color? border;

  static const AppPaletteColors yemenDrive = AppPaletteColors(
    primary: Color(0xFFFBC02D),
    primaryDark: Color(0xFFF9A825),
    secondary: Color(0xFFC8003B),
  );

  static const AppPaletteColors blueGold = AppPaletteColors(
    primary: Color(0xFF1595BE),
    primaryDark: Color(0xFF087EA6),
    secondary: Color(0xFFE4B96F),
  );

  static const AppPaletteColors midnightBurgundy = AppPaletteColors(
    // Representative solid value sampled from the supplied image.
    primary: Color(0xFF260015),
    primaryDark: Color(0xFF16000C),
    secondary: Color(0xFF8E3A68),
  );

  static const AppPaletteColors modern = AppPaletteColors(
    primary: Color(0xFF087AC1),
    primaryDark: Color(0xFF102C50),
    secondary: Color(0xFF159FCB),
    lightBackground: Color(0xFFF5F8FB),
    lightSurface: Color(0xFFFFFFFF),
    lightSurfaceAlt: Color(0xFFEAF5FF),
    lightText: Color(0xFF102C50),
    lightMuted: Color(0xFF607B95),
    darkBackground: Color(0xFF07192B),
    darkSurface: Color(0xFF102C50),
    darkSurfaceAlt: Color(0xFF173A5D),
    darkText: Color(0xFFEAF5FF),
    darkMuted: Color(0xFFB4CEE2),
    border: Color(0xFFD2E3F0),
  );
}

extension AppPaletteValues on AppPalette {
  AppPaletteColors get colors => switch (this) {
        AppPalette.yemenDrive => AppPaletteColors.yemenDrive,
        AppPalette.blueGold => AppPaletteColors.blueGold,
        AppPalette.midnightBurgundy => AppPaletteColors.midnightBurgundy,
        AppPalette.modern => AppPaletteColors.modern,
      };
}
