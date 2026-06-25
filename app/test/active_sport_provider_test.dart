import 'package:flutter_test/flutter_test.dart';
import 'package:allround/models/tournament.dart';
import 'package:allround/state/providers.dart';

void main() {
  test('primarySportFrom returns the primary registered sport', () {
    final sports = [
      UserSport(sport: 'tennis', grade: 'div4'),
      UserSport(sport: 'futsal', grade: 'intermediate', isPrimary: true),
    ];

    expect(primarySportFrom(sports), 'futsal');
  });

  test('primarySportFrom falls back to the first sport when no primary exists',
      () {
    final sports = [
      UserSport(sport: 'tennis', grade: 'div4'),
      UserSport(sport: 'futsal', grade: 'intermediate'),
    ];

    expect(primarySportFrom(sports), 'tennis');
  });
}
