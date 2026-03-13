import 'package:flutter/material.dart';

class NetSpecterTheme {
  static const Color surface = Color(0xFF121212);
  static const Color surfaceContainer = Color(0xFF1E1E1E);

  static const Color textPrimary = Color(0xFFF3F4F6);
  static const Color textSecondary = Color(0xFFE5E7EB); // gray-200
  static const Color textTertiary = Color(0xFFD1D5DB); // gray-300
  static const Color textQuaternary = Color(0xFF9CA3AF); // gray-400
  static const Color textMuted = Color(0xFF6B7280); // gray-500

  // Brand / Action colors
  static const Color indigo500 = Color(0xFF6366F1);
  static const Color indigo400 = Color(0xFF818CF8);

  // Status & Method colors
  static const Color green500 = Color(0xFF22C55E);
  static const Color green400 = Color(0xFF4ADE80);

  static const Color blue500 = Color(0xFF3B82F6);
  static const Color blue400 = Color(0xFF60A5FA);

  static const Color red500 = Color(0xFFEF4444);
  static const Color red400 = Color(0xFFF87171);

  static const Color yellow500 = Color(0xFFEAB308);
  static const Color yellow400 = Color(0xFFFACC15);

  static const Color purple100 = Color(0xFFF3E8FF);
  static const Color purple300 = Color(0xFFD8B4FE);
  static const Color purple400 = Color(0xFFC084FC);
  static const Color purple500 = Color(0xFFA855F7);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: surface,
      primaryColor: indigo500,
      colorScheme: const ColorScheme.dark(
        primary: indigo500,
        surface: surface,
        surfaceContainer: surfaceContainer,
        onSurface: textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: textQuaternary),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        elevation: 0,
        selectedItemColor: indigo400,
        unselectedItemColor: textMuted,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle:
            TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
        unselectedLabelStyle:
            TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: indigo500,
        selectionColor: Color(0x406366F1), // indigo500 / 25%
        selectionHandleColor: indigo500,
      ),
    );
  }

  // Helper styles matching ui.html
  static MethodStyle getMethodStyle(String method) {
    switch (method.toUpperCase()) {
      case 'GET':
        return MethodStyle(
          bg: green500.withValues(alpha: 0.15),
          border: green500.withValues(alpha: 0.3),
          text: green400,
        );
      case 'POST':
        return MethodStyle(
          bg: blue500.withValues(alpha: 0.15),
          border: blue500.withValues(alpha: 0.3),
          text: blue400,
        );
      case 'DELETE':
        return MethodStyle(
          bg: red500.withValues(alpha: 0.15),
          border: red500.withValues(alpha: 0.3),
          text: red400,
        );
      case 'WS':
        return MethodStyle(
          bg: purple500.withValues(alpha: 0.15),
          border: purple500.withValues(alpha: 0.3),
          text: purple400,
        );
      default:
        return MethodStyle(
          bg: textMuted.withValues(alpha: 0.15),
          border: textMuted.withValues(alpha: 0.3),
          text: textQuaternary,
        );
    }
  }

  static StatusStyle getStatusStyle(int status) {
    if (status >= 200 && status < 300) {
      return const StatusStyle(bg: green500, text: Colors.black);
    }
    if (status >= 400 && status < 500) {
      return const StatusStyle(bg: yellow500, text: Colors.black);
    }
    if (status >= 500) {
      return const StatusStyle(bg: red500, text: Colors.white);
    }
    if (status == 101) {
      return const StatusStyle(bg: purple500, text: Colors.white);
    }
    return const StatusStyle(bg: textMuted, text: Colors.white);
  }
}

class MethodStyle {
  final Color bg;
  final Color border;
  final Color text;

  const MethodStyle({
    required this.bg,
    required this.border,
    required this.text,
  });
}

class StatusStyle {
  final Color bg;
  final Color text;

  const StatusStyle({
    required this.bg,
    required this.text,
  });
}
