import 'package:flutter/material.dart';

const defaultClubCardColor = '#3156D8';

const clubCardColorChoices = <String>[
  '#18376D',
  '#3156D8',
  '#176B63',
  '#6941C6',
  '#C2413B',
  '#A15C08',
];

Color clubCardColor(String? value) {
  final normalized = value?.toUpperCase();
  final selected = clubCardColorChoices.contains(normalized)
      ? normalized!
      : defaultClubCardColor;
  return Color(int.parse('FF${selected.substring(1)}', radix: 16));
}
