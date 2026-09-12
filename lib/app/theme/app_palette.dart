import 'package:flutter/material.dart';

enum AppPalette { yemenDrive, blueGold, midnightBurgundy }

extension AppPaletteLabels on AppPalette {
  String get label => switch (this) {
        AppPalette.yemenDrive => 'يمن درايف',
        AppPalette.blueGold => 'الهوية الزرقاء الذهبية',
        AppPalette.midnightBurgundy => 'العنابي الليلي',
      };
}

@immutable
class AppPaletteColors {
  const AppPaletteColors({
    required this.primary,
    required this.primaryDark,
    required this.secondary,
  });

  final Color primary;
  final Color primaryDark;
  final Color secondary;

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
}

extension AppPaletteValues on AppPalette {
  AppPaletteColors get colors => switch (this) {
        AppPalette.yemenDrive => AppPaletteColors.yemenDrive,
        AppPalette.blueGold => AppPaletteColors.blueGold,
        AppPalette.midnightBurgundy => AppPaletteColors.midnightBurgundy,
      };
}
