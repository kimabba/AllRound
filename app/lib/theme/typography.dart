import 'package:flutter/material.dart';

/// Pretendard Variable 기반 한글 친화 타이포 스케일.
/// 자간 -2% (한글 가독성), 행간 1.5 (본문) ~ 1.3 (라벨).
class AppTypography {
  AppTypography._();

  static const String _family = 'Pretendard';
  static const double _trackTight = -0.5; // ~-2%
  static const double _trackBody = -0.2;

  static const TextTheme textTheme = TextTheme(
    // Display — hero 영역만
    displayLarge: TextStyle(
      fontFamily: _family,
      fontSize: 36,
      height: 1.25,
      fontWeight: FontWeight.w700,
      letterSpacing: _trackTight,
    ),
    displayMedium: TextStyle(
      fontFamily: _family,
      fontSize: 30,
      height: 1.30,
      fontWeight: FontWeight.w700,
      letterSpacing: _trackTight,
    ),

    // Headline — 화면 제목
    headlineLarge: TextStyle(
      fontFamily: _family,
      fontSize: 26,
      height: 1.30,
      fontWeight: FontWeight.w700,
      letterSpacing: _trackTight,
    ),
    headlineMedium: TextStyle(
      fontFamily: _family,
      fontSize: 22,
      height: 1.35,
      fontWeight: FontWeight.w700,
      letterSpacing: _trackTight,
    ),
    headlineSmall: TextStyle(
      fontFamily: _family,
      fontSize: 18,
      height: 1.40,
      fontWeight: FontWeight.w600,
      letterSpacing: _trackTight,
    ),

    // Title — 카드 제목
    titleLarge: TextStyle(
      fontFamily: _family,
      fontSize: 17,
      height: 1.40,
      fontWeight: FontWeight.w600,
      letterSpacing: _trackTight,
    ),
    titleMedium: TextStyle(
      fontFamily: _family,
      fontSize: 15,
      height: 1.45,
      fontWeight: FontWeight.w600,
      letterSpacing: _trackBody,
    ),
    titleSmall: TextStyle(
      fontFamily: _family,
      fontSize: 13,
      height: 1.45,
      fontWeight: FontWeight.w600,
      letterSpacing: _trackBody,
    ),

    // Body
    bodyLarge: TextStyle(
      fontFamily: _family,
      fontSize: 16,
      height: 1.55,
      fontWeight: FontWeight.w400,
      letterSpacing: _trackBody,
    ),
    bodyMedium: TextStyle(
      fontFamily: _family,
      fontSize: 14,
      height: 1.55,
      fontWeight: FontWeight.w400,
      letterSpacing: _trackBody,
    ),
    bodySmall: TextStyle(
      fontFamily: _family,
      fontSize: 12,
      height: 1.50,
      fontWeight: FontWeight.w400,
      letterSpacing: _trackBody,
    ),

    // Label
    labelLarge: TextStyle(
      fontFamily: _family,
      fontSize: 14,
      height: 1.30,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    ),
    labelMedium: TextStyle(
      fontFamily: _family,
      fontSize: 12,
      height: 1.30,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    ),
    labelSmall: TextStyle(
      fontFamily: _family,
      fontSize: 11,
      height: 1.30,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    ),
  );
}
