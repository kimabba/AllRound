import 'package:allround/models/rule_quiz.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('풋살과 테니스 퀴즈가 각각 3개 준비되어 있다', () {
    expect(futsalRuleQuizzes, hasLength(3));
    expect(tennisRuleQuizzes, hasLength(3));
  });

  test('오늘의 퀴즈는 한국 날짜가 바뀌면 다음 문제로 순환한다', () {
    final first = dailyRuleQuiz('futsal', now: DateTime.utc(2026, 8, 18, 15));
    final second = dailyRuleQuiz('futsal', now: DateTime.utc(2026, 8, 19, 15));

    expect(identical(first, second), isFalse);
  });
}
