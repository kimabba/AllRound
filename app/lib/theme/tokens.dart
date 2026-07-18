import 'package:flutter/material.dart';

/// PureForm Sports shape scale.
///
/// 화면의 정보 밀도를 높이고 장식적인 라운드를 줄인다. 큰 pill 은 필터와
/// 상태처럼 의미가 있는 경우에만 사용한다.
class AppRadius {
  AppRadius._();
  static const double xs = 3;
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 10;
  static const double xl = 12;
  static const double xxl = 16;
  static const double full = 999; // pill

  static const BorderRadius card = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius hero = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius sheet = BorderRadius.vertical(
    top: Radius.circular(xxl),
  );
  static const BorderRadius pill = BorderRadius.all(Radius.circular(full));
}

/// 8pt 그리드
class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 40;

  static const EdgeInsets screen = EdgeInsets.symmetric(
    horizontal: xl,
    vertical: md,
  );
  static const EdgeInsets cardInner = EdgeInsets.all(lg);
  static const EdgeInsets listGap = EdgeInsets.symmetric(vertical: sm);
}

/// 그림자는 오버레이에만 사용한다. 일반 카드의 깊이는 선과 여백으로 표현한다.
class AppShadows {
  AppShadows._();

  static const List<BoxShadow> card = [];

  static const List<BoxShadow> elevated = [];

  static const List<BoxShadow> overlay = [
    BoxShadow(color: Color(0x0F1E2A44), blurRadius: 32, offset: Offset(0, 12)),
  ];

  static List<BoxShadow>? cardFor(Brightness b) => null;

  static List<BoxShadow>? elevatedFor(Brightness b) => null;
}

/// 종목은 색이 아니라 레이블과 정보 구조로 구분한다.
/// 전 화면의 액센트를 하나로 잠가 시각적 소음을 줄인다.
class AppSportColors {
  AppSportColors._();
  static const Color tennis = Color(0xFF3156D8);
  static const Color futsal = Color(0xFF3156D8);

  static Color forSport(String sport) => sport == 'futsal' ? futsal : tennis;
}
