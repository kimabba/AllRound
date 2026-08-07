import 'package:flutter/material.dart';

/// 올라운드 PureForm Sports 팔레트.
class AppPalette {
  AppPalette._();
  static const Color accent = Color(0xFF3156D8);
  static const Color accentPressed = Color(0xFF2747B8);
  static const Color accentTint = Color(0xFFEDF1FF);
  static const Color canvas = Color(0xFFF4F5F7);
  static const Color surface = Color(0xFFFCFCFB);
  static const Color text = Color(0xFF161616);
  static const Color textMuted = Color(0xFF6F7176);
  static const Color border = Color(0xFFE5E6E8);

  // 기존 참조를 깨지 않기 위한 의미 호환 별칭.
  static const Color primaryBlue = accent;
  static const Color primaryBlueSoft = accentPressed;
  static const Color primaryBlueTint = accentTint;
  static const Color futsalGreen = accent;
  static const Color futsalGreenDark = accentPressed;
  static const Color futsalGreenSoft = accentTint;
  static const Color tennisOrange = accent;
  static const Color tennisOrangeDark = accentPressed;
  static const Color tennisOrangeSoft = accentTint;
  static const Color appBackground = canvas;
}

/// 대회·클럽 화면의 다이어리형 정보 구분 팔레트.
///
/// 기능 상태를 대신하지 않고 콘텐츠 묶음을 부드럽게 구분한다.
class AppDiaryColors {
  AppDiaryColors._();

  static const Color roseLight = Color(0xFFFBE7EF);
  static const Color roseDark = Color(0xFF563746);
  static const Color lavenderLight = Color(0xFFEDE8FB);
  static const Color lavenderDark = Color(0xFF403A59);
  static const Color roseAccentLight = Color(0xFFB64270);
  static const Color roseAccentDark = Color(0xFFFF9DBE);

  static Color rose(Brightness brightness) =>
      brightness == Brightness.dark ? roseDark : roseLight;

  static Color lavender(Brightness brightness) =>
      brightness == Brightness.dark ? lavenderDark : lavenderLight;

  static Color roseAccent(Brightness brightness) =>
      brightness == Brightness.dark ? roseAccentDark : roseAccentLight;
}

/// Light Color Scheme. 차가운 뉴트럴과 코발트 한 색으로 잠근다.
const ColorScheme appLightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: AppPalette.accent,
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: AppPalette.accentTint,
  onPrimaryContainer: Color(0xFF203A99),
  secondary: AppPalette.accent,
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: AppPalette.accentTint,
  onSecondaryContainer: Color(0xFF203A99),
  tertiary: AppPalette.accent,
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: AppPalette.accentTint,
  onTertiaryContainer: Color(0xFF203A99),
  error: Color(0xFFB42318),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFFE9E7),
  onErrorContainer: Color(0xFF7A271A),
  surface: AppPalette.surface,
  onSurface: AppPalette.text,
  onSurfaceVariant: AppPalette.textMuted,
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFF9F9F8),
  surfaceContainer: AppPalette.canvas,
  surfaceContainerHigh: Color(0xFFEEF0F3),
  surfaceContainerHighest: Color(0xFFE6E8EB),
  outline: Color(0xFF9A9CA1),
  outlineVariant: AppPalette.border,
  shadow: Color(0xFF1E2A44),
  scrim: Color(0xFF111318),
  inverseSurface: Color(0xFF1A1A1A),
  onInverseSurface: Color(0xFFF8F8F7),
  inversePrimary: Color(0xFF9FB1FF),
);

/// Dark Color Scheme. 같은 코발트와 차가운 뉴트럴 계열을 유지한다.
const ColorScheme appDarkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFF9FB1FF),
  onPrimary: Color(0xFF10235F),
  primaryContainer: Color(0xFF233B91),
  onPrimaryContainer: Color(0xFFDDE3FF),
  secondary: Color(0xFF9FB1FF),
  onSecondary: Color(0xFF10235F),
  secondaryContainer: Color(0xFF233B91),
  onSecondaryContainer: Color(0xFFDDE3FF),
  tertiary: Color(0xFF9FB1FF),
  onTertiary: Color(0xFF10235F),
  tertiaryContainer: Color(0xFF233B91),
  onTertiaryContainer: Color(0xFFDDE3FF),
  error: Color(0xFFFFB4AB),
  onError: Color(0xFF690005),
  errorContainer: Color(0xFF93000A),
  onErrorContainer: Color(0xFFFFDAD6),
  surface: Color(0xFF151619),
  onSurface: Color(0xFFF2F2F0),
  onSurfaceVariant: Color(0xFFB7B9BE),
  surfaceContainerLowest: Color(0xFF101114),
  surfaceContainerLow: Color(0xFF1B1C20),
  surfaceContainer: Color(0xFF202126),
  surfaceContainerHigh: Color(0xFF292A30),
  surfaceContainerHighest: Color(0xFF33343B),
  outline: Color(0xFF8D8F96),
  outlineVariant: Color(0xFF3B3D44),
  shadow: Color(0xFF08090B),
  scrim: Color(0xFF08090B),
  inverseSurface: Color(0xFFF2F2F0),
  onInverseSurface: Color(0xFF25262A),
  inversePrimary: AppPalette.accent,
);
