import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const ink = Color(0xFF172B4D);
  static const navy = Color(0xFF14233F);
  static const blue = Color(0xFF315E9E);
  static const teal = Color(0xFF168C83);
  static const canvas = Color(0xFFF3F6FA);
  static const muted = Color(0xFF68778D);
  static const line = Color(0xFFE5EAF1);
  static const radius = 14.0;
  static const cardRadius = 18.0;
  static const pagePadding = 16.0;
  static const fieldHeight = 48.0;
  static const error = Color(0xFFB5473C);

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: blue,
      brightness: Brightness.light,
      surface: Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(
        primary: blue,
        secondary: teal,
        surface: Colors.white,
        onSurface: ink,
      ),
      scaffoldBackgroundColor: canvas,
      visualDensity: VisualDensity.standard,
      appBarTheme: const AppBarTheme(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 16,
        toolbarHeight: 56,
        titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: const BorderSide(color: line, width: 0.8),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(cardRadius)),
        titleTextStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: ink),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: canvas,
        modalBackgroundColor: canvas,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        hintStyle: const TextStyle(color: muted, fontSize: 13),
        labelStyle: const TextStyle(color: muted, fontSize: 14),
        floatingLabelStyle: const TextStyle(color: blue, fontSize: 14),
        errorStyle: const TextStyle(color: error, fontSize: 12),
        errorMaxLines: 2,
        prefixIconColor: muted,
        suffixIconColor: muted,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: const BorderSide(color: blue, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: const BorderSide(color: error)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: const BorderSide(color: error, width: 1.5)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: blue,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, fieldHeight),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: blue,
          side: const BorderSide(color: line),
          minimumSize: const Size(0, fieldHeight),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: blue,
          minimumSize: const Size(0, 44),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: canvas,
        selectedColor: const Color(0xFFE7EEF7),
        side: const BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: const TextStyle(fontSize: 12, color: ink),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: blue, foregroundColor: Colors.white, elevation: 3,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: blue),
      dividerTheme: const DividerThemeData(color: line, thickness: 1),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: ink),
        titleLarge: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: ink),
        titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink),
        bodyMedium: TextStyle(fontSize: 14, color: ink, height: 1.4),
        bodySmall: TextStyle(fontSize: 12, color: muted, height: 1.35),
      ),
    );
  }
}
