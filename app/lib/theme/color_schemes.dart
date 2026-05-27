import 'package:flutter/material.dart';

/// Match-up 브랜드 팔레트.
class AppPalette {
  AppPalette._();
  static const Color primaryBlue = Color(0xFF1E3A8A);
  static const Color primaryBlueSoft = Color(0xFF3B5BDB);
  static const Color primaryBlueTint = Color(0xFFEEF2FF);
  static const Color futsalGreen = Color(0xFF84CC16);
  static const Color futsalGreenDark = Color(0xFF65A30D);
  static const Color futsalGreenSoft = Color(0xFFECFCCB);
  static const Color tennisOrange = Color(0xFFF97316);
  static const Color tennisOrangeDark = Color(0xFFEA580C);
  static const Color tennisOrangeSoft = Color(0xFFFFEDD5);
  static const Color appBackground = Color(0xFFF1F5F9);
  static const Color text = Color(0xFF0F172A);
  static const Color textMuted = Color(0xFF475569);
  static const Color border = Color(0xFFE2E8F0);
}

/// Light Color Scheme — Material You 12 토큰 + surfaceContainer 5단
const ColorScheme appLightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: AppPalette.primaryBlue,
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: AppPalette.primaryBlueTint,
  onPrimaryContainer: AppPalette.primaryBlue,
  secondary: AppPalette.futsalGreen,
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: AppPalette.futsalGreenSoft,
  onSecondaryContainer: AppPalette.futsalGreenDark,
  tertiary: AppPalette.tennisOrange,
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: AppPalette.tennisOrangeSoft,
  onTertiaryContainer: AppPalette.tennisOrangeDark,
  error: Color(0xFFBA1A1A),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFFDAD6),
  onErrorContainer: Color(0xFF410002),
  surface: AppPalette.appBackground,
  onSurface: AppPalette.text,
  onSurfaceVariant: AppPalette.textMuted,
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFFFFFFF),
  surfaceContainer: Color(0xFFF8FAFC),
  surfaceContainerHigh: Color(0xFFF1F5F9),
  surfaceContainerHighest: Color(0xFFE2E8F0),
  outline: Color(0xFF94A3B8),
  outlineVariant: AppPalette.border,
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  inverseSurface: AppPalette.text,
  onInverseSurface: Color(0xFFF8FAFC),
  inversePrimary: AppPalette.primaryBlueSoft,
);

/// Dark Color Scheme — 미드나잇 그린 (#101411), 풀블랙 X
const ColorScheme appDarkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFF9BD3A2),
  onPrimary: Color(0xFF003910),
  primaryContainer: Color(0xFF12531C),
  onPrimaryContainer: Color(0xFFB6F0BC),
  secondary: Color(0xFFE8C547),
  onSecondary: Color(0xFF3A2E00),
  secondaryContainer: Color(0xFF584400),
  onSecondaryContainer: Color(0xFFFFE08A),
  tertiary: Color(0xFFFFB59B),
  onTertiary: Color(0xFF5C1900),
  tertiaryContainer: Color(0xFF822A04),
  onTertiaryContainer: Color(0xFFFFDBCC),
  error: Color(0xFFFFB4AB),
  onError: Color(0xFF690005),
  errorContainer: Color(0xFF93000A),
  onErrorContainer: Color(0xFFFFDAD6),
  surface: Color(0xFF101411),
  onSurface: Color(0xFFE2E3DD),
  onSurfaceVariant: Color(0xFFC2C8BD),
  surfaceContainerLowest: Color(0xFF0B0E0C),
  surfaceContainerLow: Color(0xFF181B17),
  surfaceContainer: Color(0xFF1C1F1B),
  surfaceContainerHigh: Color(0xFF262925),
  surfaceContainerHighest: Color(0xFF313430),
  outline: Color(0xFF8C9387),
  outlineVariant: Color(0xFF424940),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  inverseSurface: Color(0xFFE2E3DD),
  onInverseSurface: Color(0xFF2F312D),
  inversePrimary: Color(0xFF2E7D32),
);
