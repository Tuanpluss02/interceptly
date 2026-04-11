import 'package:flutter/material.dart';

class InterceptlyTheme {
  InterceptlyTheme._();

  static const String fontFamily = 'JetBrainsMono';
  static const String fontPackage = 'interceptly';

  static final ValueNotifier<Brightness> brightnessNotifier =
      ValueNotifier<Brightness>(
    WidgetsBinding.instance.platformDispatcher.platformBrightness,
  );

  static Brightness get brightness => brightnessNotifier.value;

  static void bind({BuildContext? context, ThemeMode? themeMode}) {
    final nextBrightness = _resolveBrightness(
      context: context,
      themeMode: themeMode,
    );
    if (brightnessNotifier.value != nextBrightness) {
      brightnessNotifier.value = nextBrightness;
    }
  }

  static InterceptlyTypography get typography => const InterceptlyTypography();
  static InterceptlySpacing get spacing => const InterceptlySpacing();
  static InterceptlyRadius get radius => const InterceptlyRadius();
  static InterceptlyColors get colors =>
      brightness == Brightness.dark ? _DarkColors() : _LightColors();

  static Brightness _resolveBrightness({
    BuildContext? context,
    ThemeMode? themeMode,
  }) {
    switch (themeMode) {
      case ThemeMode.light:
        return Brightness.light;
      case ThemeMode.dark:
        return Brightness.dark;
      case ThemeMode.system:
      case null:
        final ctx = context;
        if (ctx != null) {
          return MediaQuery.platformBrightnessOf(ctx);
        }
        return WidgetsBinding.instance.platformDispatcher.platformBrightness;
    }
  }

  static Color get surface => colors.surfacePrimary;
  static Color get surfaceContainer => colors.surfaceSecondary;

  static Color get textPrimary => colors.textPrimary;
  static Color get textSecondary => colors.textSecondary;
  static Color get textTertiary => colors.textTertiary;
  static const Color textQuaternary = InterceptlyGlobalColor.textQuaternary;
  static const Color textMuted = InterceptlyGlobalColor.textMuted;

  static Color get dividerSubtle => brightness == Brightness.dark
      ? InterceptlyGlobalColor.white.withValues(alpha: 0.06)
      : InterceptlyGlobalColor.black.withValues(alpha: 0.08);

  static Color get hoverOverlay => brightness == Brightness.dark
      ? InterceptlyGlobalColor.white.withValues(alpha: 0.05)
      : InterceptlyGlobalColor.black.withValues(alpha: 0.04);

  static Color get controlMuted => brightness == Brightness.dark
      ? InterceptlyGlobalColor.white.withValues(alpha: 0.1)
      : InterceptlyGlobalColor.black.withValues(alpha: 0.12);

  static const Color indigo500 = InterceptlyGlobalColor.indigo500;
  static const Color indigo400 = InterceptlyGlobalColor.indigo400;

  static const Color green500 = InterceptlyGlobalColor.green500;
  static const Color green400 = InterceptlyGlobalColor.green400;

  static const Color blue500 = InterceptlyGlobalColor.blue500;
  static const Color blue400 = InterceptlyGlobalColor.blue400;

  static const Color red500 = InterceptlyGlobalColor.red500;
  static const Color red400 = InterceptlyGlobalColor.red400;

  static const Color yellow500 = InterceptlyGlobalColor.yellow500;
  static const Color yellow400 = InterceptlyGlobalColor.yellow400;

  static const Color purple100 = InterceptlyGlobalColor.purple100;
  static const Color purple300 = InterceptlyGlobalColor.purple300;
  static const Color purple400 = InterceptlyGlobalColor.purple400;
  static const Color purple500 = InterceptlyGlobalColor.purple500;

  static ThemeData get lightTheme {
    const palette = _LightColors();
    return _buildThemeData(brightness: Brightness.light, palette: palette);
  }

  static ThemeData get darkTheme {
    const palette = _DarkColors();
    return _buildThemeData(brightness: Brightness.dark, palette: palette);
  }

  static ThemeData themeData({BuildContext? context, ThemeMode? themeMode}) {
    bind(context: context, themeMode: themeMode);
    return brightness == Brightness.dark ? darkTheme : lightTheme;
  }

  static ThemeData _buildThemeData({
    required Brightness brightness,
    required InterceptlyColors palette,
  }) {
    return ThemeData(
      brightness: brightness,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: palette.surfacePrimary,
      primaryColor: palette.actionPrimary,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: palette.actionPrimary,
        onPrimary: palette.textOnAction,
        secondary: palette.actionSecondary,
        onSecondary: palette.textOnAction,
        error: palette.errorDefault,
        onError: palette.textOnAction,
        surface: palette.surfacePrimary,
        onSurface: palette.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.surfacePrimary,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: palette.textSecondary),
        titleTextStyle: typography.titleSmallBold.copyWith(
          color: palette.textPrimary,
          letterSpacing: -0.5,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: palette.surfacePrimary,
        elevation: 0,
        selectedItemColor: palette.actionPrimary,
        unselectedItemColor: palette.textTertiary,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: typography.labelSmallMedium.copyWith(
          color: palette.actionPrimary,
        ),
        unselectedLabelStyle: typography.labelSmallMedium.copyWith(
          color: palette.textTertiary,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: palette.actionPrimary,
        selectionColor: palette.actionPrimary.withValues(alpha: 0.25),
        selectionHandleColor: palette.actionPrimary,
      ),
    );
  }

  // Helper styles matching ui.html
  static MethodStyle getMethodStyle(String method) {
    final palette = colors;
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
          bg: palette.textTertiary.withValues(alpha: 0.15),
          border: palette.textTertiary.withValues(alpha: 0.3),
          text: palette.textSecondary,
        );
    }
  }

  static StatusStyle getStatusStyle(int status) {
    if (status >= 200 && status < 300) {
      return const StatusStyle(
        bg: green500,
        text: InterceptlyGlobalColor.black,
      );
    }
    if (status >= 400 && status < 500) {
      return const StatusStyle(
        bg: yellow500,
        text: InterceptlyGlobalColor.black,
      );
    }
    if (status >= 500) {
      return const StatusStyle(bg: red500, text: InterceptlyGlobalColor.white);
    }
    if (status == 101) {
      return const StatusStyle(
        bg: purple500,
        text: InterceptlyGlobalColor.white,
      );
    }
    return const StatusStyle(bg: textMuted, text: InterceptlyGlobalColor.white);
  }
}

class InterceptlyGlobalColor {
  const InterceptlyGlobalColor();

  static const Color transparent = Color(0x00000000);
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  static const Color black12 = Color(0x1F000000);
  static const Color black26 = Color(0x42000000);
  static const Color orange = Color(0xFFFF9800);
  static const Color highlightSoft = Color(0x40FFF59D);
  static const Color highlightStrong = Color(0x80FFF59D);

  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceSecondaryLight = Color(0xFFF5F6F7);
  static const Color surfaceTertiaryLight = Color(0xFFEAECEF);

  static const Color surfaceDark = Color(0xFF121212);
  static const Color surfaceContainerDark = Color(0xFF1E1E1E);
  static const Color surfaceTertiaryDark = Color(0xFF2A2A2A);

  static const Color textPrimaryLight = Color(0xFF111827);
  static const Color textSecondaryLight = Color(0xFF374151);
  static const Color textTertiaryLight = Color(0xFF6B7280);

  static const Color textPrimaryDark = Color(0xFFF3F4F6);
  static const Color textSecondaryDark = Color(0xFFE5E7EB);
  static const Color textTertiaryDark = Color(0xFF9CA3AF);

  static const Color textQuaternary = Color(0xFF9CA3AF);
  static const Color textMuted = Color(0xFF6B7280);

  static const Color indigo500 = Color(0xFF6366F1);
  static const Color indigo400 = Color(0xFF818CF8);

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
}

class InterceptlyTypography {
  const InterceptlyTypography();

  // Display styles
  TextStyle get displayLarge => _base(32, FontWeight.w700);
  TextStyle get displayMedium => _base(28, FontWeight.w700);
  TextStyle get displaySmall => _base(24, FontWeight.w700);

  // Headline styles
  TextStyle get headlineLarge => _base(22, FontWeight.w700);
  TextStyle get headlineMedium => _base(20, FontWeight.w700);
  TextStyle get headlineSmall => _base(18, FontWeight.w700);

  // Title styles
  TextStyle get titleLargeRegular => _base(20, FontWeight.w400);
  TextStyle get titleLargeMedium => _base(20, FontWeight.w500);
  TextStyle get titleLargeBold => _base(20, FontWeight.w700);

  TextStyle get titleMediumRegular => _base(18, FontWeight.w400);
  TextStyle get titleMediumMedium => _base(18, FontWeight.w500);
  TextStyle get titleMediumBold => _base(18, FontWeight.w700);

  TextStyle get titleSmallRegular => _base(18, FontWeight.w400);
  TextStyle get titleSmallMedium => _base(18, FontWeight.w500);
  TextStyle get titleSmallBold => _base(20, FontWeight.w700);

  // Body styles
  TextStyle get bodyLargeRegular => _base(16, FontWeight.w400);
  TextStyle get bodyLargeMedium => _base(16, FontWeight.w500);
  TextStyle get bodyLargeBold => _base(16, FontWeight.w700);

  TextStyle get bodyMediumRegular => _base(14, FontWeight.w400);
  TextStyle get bodyMediumMedium => _base(14, FontWeight.w500);
  TextStyle get bodyMediumBold => _base(14, FontWeight.w700);

  TextStyle get bodySmallRegular => _base(12, FontWeight.w400);
  TextStyle get bodySmallMedium => _base(12, FontWeight.w500);
  TextStyle get bodySmallBold => _base(12, FontWeight.w700);

  // Label styles
  TextStyle get labelLargeRegular => _base(12, FontWeight.w400);
  TextStyle get labelLargeMedium => _base(12, FontWeight.w500);
  TextStyle get labelLargeBold => _base(12, FontWeight.w700);

  TextStyle get labelMediumRegular => _base(11, FontWeight.w400);
  TextStyle get labelMediumMedium => _base(11, FontWeight.w500);
  TextStyle get labelMediumBold => _base(11, FontWeight.w700);

  TextStyle get labelSmallRegular => _base(10, FontWeight.w400);
  TextStyle get labelSmallMedium => _base(10, FontWeight.w500);
  TextStyle get labelSmallBold => _base(10, FontWeight.w700);

  TextStyle copyWith(
    TextStyle base, {
    Color? color,
    TextDecoration? decoration,
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
    FontStyle? fontStyle,
  }) {
    return base.copyWith(
      color: color,
      decoration: decoration,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
      fontStyle: fontStyle,
    );
  }

  TextStyle _base(double size, FontWeight weight) {
    return TextStyle(
      fontFamily: InterceptlyTheme.fontFamily,
      package: InterceptlyTheme.fontPackage,
      fontSize: size,
      fontWeight: weight,
    );
  }
}

class InterceptlySpacing {
  const InterceptlySpacing();

  double get xs => 4;
  double get sm => 8;
  double get md => 16;
  double get lg => 24;
  double get xl => 32;
}

class InterceptlyRadius {
  const InterceptlyRadius();

  double get sm => 4;
  double get md => 8;
  double get lg => 12;
  double get full => 999;
}

abstract class InterceptlyColors {
  const InterceptlyColors();

  Color get surfacePrimary;
  Color get surfaceSecondary;
  Color get surfaceTertiary;
  Color get textPrimary;
  Color get textSecondary;
  Color get textTertiary;
  Color get textOnAction;
  Color get actionPrimary;
  Color get actionSecondary;
  Color get errorDefault;
}

class _LightColors extends InterceptlyColors {
  const _LightColors();

  @override
  Color get surfacePrimary => InterceptlyGlobalColor.surfaceLight;
  @override
  Color get surfaceSecondary => InterceptlyGlobalColor.surfaceSecondaryLight;
  @override
  Color get surfaceTertiary => InterceptlyGlobalColor.surfaceTertiaryLight;
  @override
  Color get textPrimary => InterceptlyGlobalColor.textPrimaryLight;
  @override
  Color get textSecondary => InterceptlyGlobalColor.textSecondaryLight;
  @override
  Color get textTertiary => InterceptlyGlobalColor.textTertiaryLight;
  @override
  Color get textOnAction => InterceptlyGlobalColor.white;
  @override
  Color get actionPrimary => InterceptlyTheme.indigo500;
  @override
  Color get actionSecondary => InterceptlyTheme.indigo400;
  @override
  Color get errorDefault => InterceptlyTheme.red500;
}

class _DarkColors extends InterceptlyColors {
  const _DarkColors();

  @override
  Color get surfacePrimary => InterceptlyGlobalColor.surfaceDark;
  @override
  Color get surfaceSecondary => InterceptlyGlobalColor.surfaceContainerDark;
  @override
  Color get surfaceTertiary => InterceptlyGlobalColor.surfaceTertiaryDark;
  @override
  Color get textPrimary => InterceptlyGlobalColor.textPrimaryDark;
  @override
  Color get textSecondary => InterceptlyGlobalColor.textSecondaryDark;
  @override
  Color get textTertiary => InterceptlyGlobalColor.textTertiaryDark;
  @override
  Color get textOnAction => InterceptlyGlobalColor.white;
  @override
  Color get actionPrimary => InterceptlyTheme.indigo500;
  @override
  Color get actionSecondary => InterceptlyTheme.indigo400;
  @override
  Color get errorDefault => InterceptlyTheme.red500;
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

  const StatusStyle({required this.bg, required this.text});
}
