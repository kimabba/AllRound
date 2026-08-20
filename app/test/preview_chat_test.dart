import 'package:allround/services/preview_chat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('프리뷰 볼보이는 서버 없이 대회 질문에 답한다', () async {
    final events = await previewChatStream(
      message: '가까운 대회 알려줘',
      activeSport: 'futsal',
    ).toList();

    expect(events.first.event, 'meta');
    expect(
      events.first.data['conversation_id'],
      'preview-ballboy-conversation',
    );
    expect(events.last.event, 'delta');
    expect(events.last.data['text'], contains('서울 챌린지컵'));
  });

  test('프리뷰 볼보이는 연결한 클럽 문맥으로 답한다', () async {
    final events = await previewChatStream(
      message: '여기 정보 알려줘',
      activeSport: 'futsal',
      selectedEntity: const {'type': 'club', 'id': 'preview-club'},
    ).toList();

    expect(events.last.data['text'], contains('잠실 풋살 러너스'));
    expect(events.last.data['text'], contains('신규 멤버 모집 중'));
  });
}
