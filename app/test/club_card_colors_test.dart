import 'package:allround/utils/club_card_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('club card color uses the saved palette value', () {
    expect(clubCardColor('#176B63'), const Color(0xFF176B63));
    expect(clubCardColor('#176b63'), const Color(0xFF176B63));
  });

  test('unknown club card colors fall back safely', () {
    expect(clubCardColor(null), const Color(0xFF3156D8));
    expect(clubCardColor('#FFFFFF'), const Color(0xFF3156D8));
  });
}
