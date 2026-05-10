import 'package:flutter/material.dart';

/// Match-up 브랜드 팔레트.
class AppPalette {
  AppPalette._();
  static const Color courtGreen = Color(0xFF2E7D32); // 시드
  static const Color tennisYellow = Color(0xFFE8C547);
  static const Color futsalOrange = Color(0xFFF4511E);
}

/// Light Color Scheme — Material You 12 토큰 + surfaceContainer 5단
const ColorScheme appLightScheme = ColorScheme(
  brightness: Brightness.light,

  primary: Color(0xFF2E7D32),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFB6F0BC),
  onPrimaryContainer: Color(0xFF002106),

  secondary: Color(0xFF8A6A00),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFFFE08A),
  onSecondaryContainer: Color(0xFF2A1F00),

  tertiary: Color(0xFFB23A0E),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFFFDBCC),
  onTertiaryContainer: Color(0xFF3A0E00),

  error: Color(0xFFBA1A1A),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFFDAD6),
  onErrorContainer: Color(0xFF410002),

  surface: Color(0xFFFCFDF7),
  onSurface: Color(0xFF1A1C19),
  onSurfaceVariant: Color(0xFF424940),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFF6F8F1),
  surfaceContainer: Color(0xFFF0F2EB),
  surfaceContainerHigh: Color(0xFFEAEDE5),
  surfaceContainerHighest: Color(0xFFE4E7DF),

  outline: Color(0xFF727970),
  outlineVariant: Color(0xFFC2C8BD),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  inverseSurface: Color(0xFF2F312D),
  onInverseSurface: Color(0xFFF0F2EB),
  inversePrimary: Color(0xFF9BD3A2),
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
