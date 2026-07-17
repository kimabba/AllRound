import 'package:flutter/material.dart';

/// M3 shape scale
class AppRadius {
  AppRadius._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16; // 카드
  static const double xl = 20; // hero
  static const double xxl = 28; // sheet
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
  static const double lg = 16; // 화면 좌우 기본 패딩
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 40;

  static const EdgeInsets screen = EdgeInsets.symmetric(
    horizontal: lg,
    vertical: md,
  );
  static const EdgeInsets cardInner = EdgeInsets.all(lg);
  static const EdgeInsets listGap = EdgeInsets.symmetric(vertical: sm);
}

/// 다층 그림자 — Card는 elevation 0, BoxShadow로 직접 표현
/// 다크모드는 거의 보이지 않으므로 surface 단계로 깊이 표현 (null 반환)
class AppShadows {
  AppShadows._();

  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0A0F172A), blurRadius: 1, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0F0F172A), blurRadius: 24, offset: Offset(0, 4)),
  ];

  static const List<BoxShadow> elevated = [
    BoxShadow(color: Color(0x0A0F172A), blurRadius: 2, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x140F172A), blurRadius: 24, offset: Offset(0, 8)),
  ];

  static const List<BoxShadow> overlay = [
    BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x29000000), blurRadius: 24, offset: Offset(0, 12)),
  ];

  static List<BoxShadow>? cardFor(Brightness b) =>
      b == Brightness.light ? card : null;

  static List<BoxShadow>? elevatedFor(Brightness b) =>
      b == Brightness.light ? elevated : null;
}

/// 종목 액센트 컬러 (테니스/풋살)
///
/// Active Bold 베이스라인(docs/design/active-bold-system.md): 테니스공 색을 따라
/// 테니스=그린, 풋살=오렌지. (이전 매핑과 스왑됨.) 화면에서 종목색은 항상
/// forSport()로만 참조하고 하드코딩하지 않는다.
class AppSportColors {
  AppSportColors._();
  static const Color tennis = Color(0xFF84CC16); // 그린 (테니스공 색)
  static const Color futsal = Color(0xFFF97316); // 오렌지

  static Color forSport(String sport) => sport == 'futsal' ? futsal : tennis;
}
