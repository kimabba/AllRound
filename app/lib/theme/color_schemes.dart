import 'package:flutter/material.dart';

/// 올라운드 브랜드 팔레트.
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

/// Light Color Scheme — Active Bold (크림 베이스).
/// primary = 잉크(볼드 블랙 주요 버튼), secondary = 테니스 그린(브랜드 액센트),
/// tertiary = 풋살 오렌지. surface = 크림, 카드 = 화이트.
/// (docs/design/active-bold-system.md)
const ColorScheme appLightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF1A1613), // 잉크
  onPrimary: Color(0xFFFAF7F2), // 크림
  primaryContainer: Color(0xFFECE6DA),
  onPrimaryContainer: Color(0xFF1A1613),
  // 앱 관례: sport=='tennis' ? cs.tertiary : cs.secondary.
  // 따라서 tertiary = 테니스 그린, secondary = 풋살 오렌지.
  secondary: Color(0xFFF97316), // 풋살 오렌지
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFFFEDD5),
  onSecondaryContainer: Color(0xFF9A3412),
  tertiary: Color(0xFF84CC16), // 테니스 그린
  onTertiary: Color(0xFF1A2E05),
  tertiaryContainer: Color(0xFFECFCCB),
  onTertiaryContainer: Color(0xFF3F6212),
  error: Color(0xFFBA1A1A),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFFDAD6),
  onErrorContainer: Color(0xFF410002),
  surface: Color(0xFFFAF7F2), // 크림
  onSurface: Color(0xFF1A1613), // 잉크
  onSurfaceVariant: Color(0xFF6E675B), // warm muted
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFFFFFFF),
  surfaceContainer: Color(0xFFF3EEE4),
  surfaceContainerHigh: Color(0xFFEDE7DB),
  surfaceContainerHighest: Color(0xFFE6E0D4),
  outline: Color(0xFF938B7C),
  outlineVariant: Color(0xFFE6E0D4),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  inverseSurface: Color(0xFF1A1613),
  onInverseSurface: Color(0xFFFAF7F2),
  inversePrimary: Color(0xFF84CC16),
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
