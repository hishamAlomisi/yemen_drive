import 'package:flutter/material.dart';

import 'app_palette.dart';

abstract final class AppColors {
  static Color primary = AppPaletteColors.blueGold.primary;
  static Color primaryDark = AppPaletteColors.blueGold.primaryDark;
  static Color secondary = AppPaletteColors.blueGold.secondary;

  static void setPalette(AppPalette palette) {
    final colors = palette.colors;
    primary = colors.primary;
    primaryDark = colors.primaryDark;
    secondary = colors.secondary;
  }

  static const Color success = Color(0xFF388E3C);
  static const Color warning = Color(0xFFF57F17);
  static const Color error = Color(0xFFD32F2F);

  static const Color lightBackground = Color(0xFFF8F8F8);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFFFF8DD);
  static const Color lightText = Color(0xFF1B1B1D);
  static const Color lightMuted = Color(0xFF747474);

  static const Color darkBackground = Color(0xFF0E0E0F);
  static const Color darkSurface = Color(0xFF1C1E27);
  static const Color darkSurfaceAlt = Color(0xFF262934);
  static const Color darkText = Color(0xFFF8F8F8);
  static const Color darkMuted = Color(0xFFB6B6BA);

  static const Color mapLandLight = Color(0xFFF2F1EB);
  static const Color mapRoadLight = Color(0xFFFFFFFF);
  static const Color mapLandDark = Color(0xFF24262D);
  static const Color mapRoadDark = Color(0xFF373A43);
}
