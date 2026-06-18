import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/utils/grade_labels.dart';

void main() {
  group('grade_labels', () {
    test('tennis grade order: under1y → over5y', () {
      expect(tennisGrades, ['under1y', 'y1to3', 'y3to5', 'over5y']);
    });

    test('futsal grade order', () {
      expect(futsalGrades, [
        'intro',
        'beginner',
        'intermediate',
        'advanced',
        'elite',
      ]);
    });

    test('Korean labels', () {
      expect(gradeLabel('y3to5'), '3~5년');
      expect(gradeLabel('under1y'), '1년 미만');
      expect(gradeLabel('intro'), '입문');
      expect(gradeLabel('intermediate'), '중급');
      expect(gradeLabel('elite'), '선출');
      expect(sportLabel(Sport.tennis), '테니스');
      expect(sportLabel(Sport.futsal), '풋살');
    });

    test('sportFromString roundtrip', () {
      expect(sportFromString('tennis'), Sport.tennis);
      expect(sportFromString('futsal'), Sport.futsal);
      expect(sportToString(Sport.tennis), 'tennis');
      expect(sportToString(Sport.futsal), 'futsal');
    });

    test('gradesFor returns sport-specific grades', () {
      expect(gradesFor(Sport.tennis), tennisGrades);
      expect(gradesFor(Sport.futsal), futsalGrades);
    });
  });
}
