import 'package:flutter/material.dart';

enum AppPalette { yemenDrive, blueGold, midnightBurgundy, modern, lime, olive }

extension AppPaletteLabels on AppPalette {
  String get label => switch (this) {
        AppPalette.yemenDrive => 'يمن درايف',
        AppPalette.blueGold => 'الهوية الزرقاء الذهبية',
        AppPalette.midnightBurgundy => 'العنابي الليلي',
        AppPalette.modern => 'ثيم مودرن',
        AppPalette.lime => 'التصميم الجديد',
        AppPalette.olive => 'الثيم الزيتي',
      };
}

@immutable
class AppPaletteColors {
  const AppPaletteColors({
    required this.primary,
    required this.primaryDark,
    required this.secondary,
    this.darkPrimary,
    this.darkPrimaryDark,
    this.darkSecondary,
    this.onPrimary,
    this.darkOnPrimary,
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
  final Color? darkPrimary;
  final Color? darkPrimaryDark;
  final Color? darkSecondary;
  final Color? onPrimary;
  final Color? darkOnPrimary;
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

  // The green and gold match the rider splash artwork.
  static const AppPaletteColors olive = AppPaletteColors(
    primary: Color(0xFF003C30),
    primaryDark: Color(0xFF003C30),
    secondary: Color(0xFF075244),
    onPrimary: Colors.white,
    lightBackground: Color(0xFFF6F8F5),
    lightSurface: Colors.white,
    lightSurfaceAlt: Color(0xFFEAF1EC),
    lightText: Color(0xFF142D25),
    lightMuted: Color(0xFF53685E),
    darkPrimary: Color(0xFFFFD46B),
    darkPrimaryDark: Color(0xFFFFD46B),
    darkSecondary: Color(0xFFEAC875),
    darkOnPrimary: Color(0xFF003C30),
    darkBackground: Color(0xFF003C30),
    darkSurface: Color(0xFF003C30),
    darkSurfaceAlt: Color(0xFF0D5041),
    darkText: Color(0xFFFFFCF4),
    darkMuted: Color(0xFFBBD0C5),
  );

  static const AppPaletteColors lime = AppPaletteColors(
    primary: Color(0xFFC1F11D),
    primaryDark: Color(0xFF526B00),
    secondary: Color(0xFF252525),
    lightBackground: Color(0xFFF4F4F0),
    lightSurface: Color(0xFFFFFFFF),
    lightSurfaceAlt: Color(0xFFF2F3EE),
    lightText: Color(0xFF202020),
    lightMuted: Color(0xFF777973),
    darkBackground: Color(0xFF141512),
    darkSurface: Color(0xFF20221D),
    darkSurfaceAlt: Color(0xFF2C2F27),
    darkText: Color(0xFFF6F7F2),
    darkMuted: Color(0xFFB9BDB0),
  );

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
        AppPalette.lime => AppPaletteColors.lime,
        AppPalette.olive => AppPaletteColors.olive,
      };
}
