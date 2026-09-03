import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.darkBackground,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.primary,
      secondary: AppColors.purpleAccent,
      surface: AppColors.darkCard,
      error: AppColors.redVideo,
    ),
    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).copyWith(
      headlineLarge: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: AppColors.darkTextPrimary,
        letterSpacing: -0.5,
      ),
      headlineMedium: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: AppColors.darkTextPrimary,
        letterSpacing: -0.3,
      ),
      titleMedium: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.darkTextPrimary,
      ),
      bodyMedium: const TextStyle(
        fontSize: 13,
        color: AppColors.darkTextSecondary,
      ),
      bodySmall: const TextStyle(
        fontSize: 11,
        color: AppColors.darkTextMuted,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.darkCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.darkBorder, width: 1),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.darkBorder,
      thickness: 1,
      space: 1,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(AppColors.darkBorder),
      radius: const Radius.circular(8),
      thickness: WidgetStateProperty.all(6),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF1C1F26),
      contentTextStyle: const TextStyle(
        color: AppColors.darkTextPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.darkBorder, width: 1),
      ),
      behavior: SnackBarBehavior.floating,
      elevation: 8,
    ),
  );

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.lightBackground,
    colorScheme: const ColorScheme.light(
      primary: AppColors.primary,
      secondary: AppColors.purpleAccent,
      surface: AppColors.lightCard,
      error: AppColors.redVideo,
    ),
    textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme).copyWith(
      headlineLarge: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: AppColors.lightTextPrimary,
        letterSpacing: -0.5,
      ),
      headlineMedium: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: AppColors.lightTextPrimary,
        letterSpacing: -0.3,
      ),
      titleMedium: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.lightTextPrimary,
      ),
      bodyMedium: const TextStyle(
        fontSize: 13,
        color: AppColors.lightTextSecondary,
      ),
      bodySmall: const TextStyle(
        fontSize: 11,
        color: AppColors.lightTextMuted,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.lightCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.lightBorder, width: 1),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.lightBorder,
      thickness: 1,
      space: 1,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(AppColors.lightBorder),
      radius: const Radius.circular(8),
      thickness: WidgetStateProperty.all(6),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF1E293B),
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      behavior: SnackBarBehavior.floating,
      elevation: 8,
    ),
  );
}
