import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

class AppTheme {
  // Premium color palette
  static const Color bgDeep       = Color(0xFF06060E);
  static const Color bgCard       = Color(0xFF0F0F1E);
  static const Color bgSurface    = Color(0xFF161628);
  static const Color accentViolet = Color(0xFF7C3AED);
  static const Color accentCyan   = Color(0xFF06B6D4);
  static const Color accentPink   = Color(0xFFEC4899);
  static const Color textPrimary  = Color(0xFFF1F5FF);
  static const Color textSecondary= Color(0xFF8892AA);
  static const Color glowViolet   = Color(0x557C3AED);
  static const Color glowCyan     = Color(0x3306B6D4);

  static ThemeData dark(Color accent) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: accent,
      fontFamily: 'Poppins',
      scaffoldBackgroundColor: bgDeep,
      cardColor: bgCard,
      appBarTheme: const AppBarTheme(
        backgroundColor: bgDeep,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: 0.5,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: bgCard,
        indicatorColor: accent.withOpacity(0.18),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w500),
        ),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black,
        elevation: 12,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        thumbColor: Colors.white,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        inactiveTrackColor: Colors.white12,
        overlayColor: accent.withOpacity(0.15),
        trackHeight: 3,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? accent : Colors.grey,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? accent.withOpacity(0.4)
              : Colors.white12,
        ),
      ),
    );
  }

  static ThemeData light(Color accent) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorSchemeSeed: accent,
      fontFamily: 'Poppins',
      scaffoldBackgroundColor: const Color(0xFFF5F5FA),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static Color accentColor(int index) {
    return AppConstants.accentColors[index % AppConstants.accentColors.length];
  }
}
