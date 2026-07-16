class ChatFollowUpSuggestion {
  const ChatFollowUpSuggestion({
    required this.label,
    required this.message,
  });

  final String label;
  final String message;
}

List<ChatFollowUpSuggestion> chatFollowUpSuggestions(
  String userMessage, {
  required String? sport,
}) {
  final query = userMessage.trim().toLowerCase();
  final sportLabel = sport == 'futsal' ? '풀살' : '테니스';

  if (_containsAny(query, const ['신청', '접수', '신청서'])) {
    return const [
      ChatFollowUpSuggestion(
        label: '신청 자격은?',
        message: '대회 신청 자격도 알려줘',
      ),
      ChatFollowUpSuggestion(
        label: '준비 서류는?',
        message: '대회 신청할 때 준비할 서류를 알려줘',
      ),
      ChatFollowUpSuggestion(
        label: '신청 가능 대회',
        message: '지금 신청 가능한 대회만 보여줘',
      ),
    ];
  }

  if (_containsAny(query, const ['대회', '일정', '경기'])) {
    return const [
      ChatFollowUpSuggestion(
        label: '내 등급에 맞는 대회',
        message: '내 등급에 맞는 대회를 찾아줘',
      ),
      ChatFollowUpSuggestion(
        label: '이번 주말 대회',
        message: '이번 주말에 열리는 대회를 알려줘',
      ),
      ChatFollowUpSuggestion(
        label: '신청 방법은?',
        message: '대회 신청 방법을 알려줘',
      ),
    ];
  }

  if (_containsAny(query, const ['클럽', '동호회', '팀'])) {
    return [
      ChatFollowUpSuggestion(
        label: '내 지역 클럽',
        message: '내 지역의 $sportLabel 클럽을 찾아줘',
      ),
      const ChatFollowUpSuggestion(
        label: '가입 방법은?',
        message: '클럽 가입 방법을 알려줘',
      ),
      const ChatFollowUpSuggestion(
        label: '클럽 선택 팁',
        message: '나에게 맞는 클럽 고르는 법을 알려줘',
      ),
    ];
  }

  if (_containsAny(query, const ['규칙', '룰', '파울', '점수'])) {
    final scoreMessage =
        sport == 'futsal' ? '풀살 경기 시간과 점수 규칙을 알려줘' : '테니스 세트와 점수 계산법을 알려줘';
    return [
      ChatFollowUpSuggestion(label: '점수 계산법', message: scoreMessage),
      ChatFollowUpSuggestion(
        label: '주의할 규칙',
        message: '$sportLabel에서 자주 틀리는 규칙을 알려줘',
      ),
      ChatFollowUpSuggestion(
        label: '실전 예시',
        message: '$sportLabel 규칙을 실전 상황으로 예시해줘',
      ),
    ];
  }

  if (_containsAny(query, const ['구장', '체육관', '장소', '예약'])) {
    return [
      ChatFollowUpSuggestion(
        label: '가까운 구장',
        message: '내 주변 $sportLabel 구장을 찾아줘',
      ),
      const ChatFollowUpSuggestion(
        label: '예약과 요금',
        message: '구장 예약 방법과 요금을 알려줘',
      ),
      const ChatFollowUpSuggestion(
        label: '시설 비교',
        message: '추천 구장들의 시설과 위치를 비교해줘',
      ),
    ];
  }

  return [
    const ChatFollowUpSuggestion(
      label: '관련 대회 찾기',
      message: '이 내용과 관련된 대회를 찾아줘',
    ),
    ChatFollowUpSuggestion(
      label: '클럽도 보기',
      message: '관련된 $sportLabel 클럽도 추천해줘',
    ),
    ChatFollowUpSuggestion(
      label: '규칙도 물어보기',
      message: '$sportLabel 기본 규칙도 알려줘',
    ),
  ];
}

bool _containsAny(String value, List<String> keywords) =>
    keywords.any(value.contains);
