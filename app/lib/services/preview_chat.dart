import 'api.dart';

/// 서버에 연결하지 않는 사용자 디자인 프리뷰 전용 볼보이 응답.
///
/// 실제 앱 빌드에서는 [ChatApi.chat]을 사용하며, 이 스트림은
/// `USER_DESIGN_PREVIEW=true`일 때만 호출된다.
Stream<ChatStreamEvent> previewChatStream({
  required String message,
  String? activeSport,
  Map<String, String>? selectedEntity,
}) async* {
  yield ChatStreamEvent('meta', const {
    'conversation_id': 'preview-ballboy-conversation',
  });

  // 전송 직후 진행 상태가 보인 다음 자연스럽게 답변이 나타나게 한다.
  await Future<void>.delayed(const Duration(milliseconds: 180));
  yield ChatStreamEvent('delta', {
    'text': _previewAnswer(
      message: message,
      activeSport: activeSport,
      selectedEntity: selectedEntity,
    ),
  });
}

String _previewAnswer({
  required String message,
  String? activeSport,
  Map<String, String>? selectedEntity,
}) {
  final normalized = message.toLowerCase();
  final sport = activeSport == 'tennis' ? '테니스' : '풋살';
  final hasClubContext = selectedEntity?['type'] == 'club';

  if (normalized.contains('클럽') || hasClubContext) {
    return '현재 프리뷰에서는 **잠실 풋살 러너스**를 기준으로 보여드릴게요.\n\n'
        '- 활동 지역: 서울 송파구\n'
        '- 정기 운동: 매주 화·목 오후 8시\n'
        '- 모집 상태: 신규 멤버 모집 중\n\n'
        '클럽 탭에서 소개, 사진, 모집 글까지 확인할 수 있어요.';
  }
  if (normalized.contains('대회') ||
      normalized.contains('신청') ||
      normalized.contains('경기')) {
    return '가까운 $sport 대회를 찾았어요. **서울 챌린지컵**은 다음 달 잠실에서 열리고, '
        '신청 마감은 이번 주 일요일이에요. 대회 탭에서 참가 조건과 준비물을 확인해 보세요.';
  }
  if (normalized.contains('룰') ||
      normalized.contains('규칙') ||
      normalized.contains('반칙')) {
    return '$sport 규칙을 쉽게 설명해 드릴게요. 궁금한 상황을 한 문장으로 적어주시면 '
        '판정 기준과 실제 경기 예시를 함께 알려드려요.';
  }
  return '네, 볼보이가 확인했어요. 지금 보고 있는 프리뷰 데이터 기준으로 '
      '대회 찾기, 클럽 가입, 경기 규칙을 물어보면 바로 안내해 드릴게요.';
}
