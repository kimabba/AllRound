import 'package:flutter_test/flutter_test.dart';
import 'package:allround/utils/chat_follow_up_suggestions.dart';

void main() {
  test('대회 신청 질문 다음에 자격과 서류 질문을 제안한다', () {
    final suggestions = chatFollowUpSuggestions(
      '대회 신청 방법 알려줘',
      sport: 'tennis',
    );

    expect(suggestions, hasLength(3));
    expect(suggestions.map((item) => item.message), contains('대회 신청 자격도 알려줘'));
    expect(
      suggestions.map((item) => item.message),
      contains('대회 신청할 때 준비할 서류를 알려줘'),
    );
  });

  test('클럽 질문은 현재 종목에 맞는 후속 질문을 제안한다', () {
    final suggestions = chatFollowUpSuggestions(
      '클럽 추천해줘',
      sport: 'futsal',
    );

    expect(suggestions.first.message, contains('풀살'));
    expect(suggestions.map((item) => item.label), contains('가입 방법은?'));
  });
}
