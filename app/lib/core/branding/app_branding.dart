import 'package:flutter/material.dart';

/// Plotspotting brand colors and assets.
abstract final class AppBranding {
  static const name = 'Plotspotting';

  static const logoAsset = 'assets/branding/logo.png';
  static const splashAsset = 'assets/branding/splash.png';

  static const navy = Color(0xFF1A2B4C);
  static const orange = Color(0xFFF27A30);
  static const cream = Color(0xFFF5F0E8);

  static ThemeData theme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: navy,
      primary: navy,
      secondary: orange,
      surface: cream,
      brightness: Brightness.light,
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: cream,
      appBarTheme: const AppBarTheme(
        backgroundColor: cream,
        foregroundColor: navy,
        elevation: 0,
        centerTitle: false,
      ),
      useMaterial3: true,
    );
  }
}
