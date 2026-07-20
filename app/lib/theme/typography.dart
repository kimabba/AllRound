import 'package:flutter/material.dart';

/// Pretendard Variable 기반의 스포츠 편집형 타이포 스케일.
/// 큰 숫자와 제목은 단단하게, 본문은 여유 있게 읽힌다.
class AppTypography {
  AppTypography._();

  static const String _family = 'Pretendard';
  static const double _trackTight = -0.9;
  static const double _trackBody = -0.18;

  static const TextTheme textTheme = TextTheme(
    // Display — hero 영역만
    displayLarge: TextStyle(
      fontFamily: _family,
      fontSize: 40,
      height: 1.08,
      fontWeight: FontWeight.w800,
      letterSpacing: _trackTight,
    ),
    displayMedium: TextStyle(
      fontFamily: _family,
      fontSize: 34,
      height: 1.10,
      fontWeight: FontWeight.w800,
      letterSpacing: _trackTight,
    ),

    // Headline — 화면 제목
    headlineLarge: TextStyle(
      fontFamily: _family,
      fontSize: 29,
      height: 1.14,
      fontWeight: FontWeight.w800,
      letterSpacing: _trackTight,
    ),
    headlineMedium: TextStyle(
      fontFamily: _family,
      fontSize: 23,
      height: 1.18,
      fontWeight: FontWeight.w700,
      letterSpacing: _trackTight,
    ),
    headlineSmall: TextStyle(
      fontFamily: _family,
      fontSize: 19,
      height: 1.24,
      fontWeight: FontWeight.w700,
      letterSpacing: _trackTight,
    ),

    // Title — 카드 제목
    titleLarge: TextStyle(
      fontFamily: _family,
      fontSize: 17,
      height: 1.40,
      fontWeight: FontWeight.w700,
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
      fontWeight: FontWeight.w700,
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
