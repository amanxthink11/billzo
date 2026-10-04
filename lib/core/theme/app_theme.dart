import 'package:flutter/material.dart';
import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/core/theme/typography.dart';

/// Billzo Application Theme configuration.
class BillzoTheme {
  BillzoTheme._();

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: BillzoTypography.fontFamily,
      brightness: Brightness.light,
      scaffoldBackgroundColor: BillzoColors.canvasLight,
      colorScheme: const ColorScheme.light(
        primary: BillzoColors.primaryBlue,
        secondary: BillzoColors.secondaryBlue,
        surface: BillzoColors.cardSurface,
        error: BillzoColors.dangerRed,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: BillzoColors.darkSlate,
        onError: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: BillzoColors.cardSurface,
        foregroundColor: BillzoColors.darkSlate,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: BillzoTypography.headline2,
        iconTheme: IconThemeData(color: BillzoColors.darkSlate),
      ),
      cardTheme: CardThemeData(
        color: BillzoColors.cardSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: BillzoColors.border, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: BillzoColors.primaryBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            fontFamily: BillzoTypography.fontFamily,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: BillzoColors.darkSlate,
          side: const BorderSide(color: BillzoColors.border, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            fontFamily: BillzoTypography.fontFamily,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: BillzoColors.cardSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        hintStyle: const TextStyle(
          color: BillzoColors.neutralText,
          fontSize: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: BillzoColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: BillzoColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: BillzoColors.primaryBlue, width: 1.5),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: BillzoColors.border,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
