import 'package:allround/utils/chat_content.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('removes parenthesized internal database id', () {
    const id = '11111111-1111-1111-1111-111111111111';

    expect(
      cleanAssistantContent('대회 신청 방법입니다. (id: $id)'),
      '대회 신청 방법입니다.',
    );
    expect(
      cleanAssistantContent('대회 안내 (ID: $id) 다음 내용'),
      '대회 안내  다음 내용',
    );
  });

  test('preserves ordinary user-visible content', () {
    expect(
      cleanAssistantContent('대회 상세 화면에서 신청 링크를 눌러주세요.'),
      '대회 상세 화면에서 신청 링크를 눌러주세요.',
    );
  });
}
