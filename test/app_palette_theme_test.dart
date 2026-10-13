import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yemen_drive/app/theme/app_palette.dart';
import 'package:yemen_drive/app/theme/app_theme.dart';

void main() {
  test('modern palette uses the requested light and dark colors', () {
    final light = AppTheme.lightFor(palette: AppPalette.modern);
    final dark = AppTheme.darkFor(palette: AppPalette.modern);

    expect(AppPalette.modern.label, 'ثيم مودرن');
    expect(light.colorScheme.primary, const Color(0xFF087AC1));
    expect(light.colorScheme.secondary, const Color(0xFF159FCB));
    expect(light.scaffoldBackgroundColor, const Color(0xFFF5F8FB));
    expect(light.cardTheme.color, Colors.white);
    expect(dark.scaffoldBackgroundColor, const Color(0xFF07192B));
    expect(dark.colorScheme.surface, const Color(0xFF102C50));
  });

  test('existing palette colors remain unchanged', () {
    final blueGold = AppTheme.lightFor(palette: AppPalette.blueGold);
    final yemenDrive = AppTheme.lightFor(palette: AppPalette.yemenDrive);

    expect(blueGold.colorScheme.primary, const Color(0xFF1595BE));
    expect(blueGold.colorScheme.secondary, const Color(0xFFE4B96F));
    expect(yemenDrive.colorScheme.primary, const Color(0xFFFBC02D));
    expect(yemenDrive.colorScheme.secondary, const Color(0xFFC8003B));
  });
}
