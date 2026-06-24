// 채팅 a2ui 카드 모델. 서버 `ui` SSE 이벤트의 blocks 를 타입 안전하게 파싱한다.
// 파싱 실패는 예외 대신 빈 결과로 흡수해 마크다운 답변이 항상 렌더되도록 한다.

/// 요강 요약 한 줄 (예: {label: '사용구', value: '헤드 챔피언십'}).
class RegulationField {
  final String label;
  final String value;

  const RegulationField({required this.label, required this.value});

  /// label/value 가 모두 비어있지 않은 String 일 때만 반환, 아니면 null.
  static RegulationField? tryFromJson(Map<String, dynamic> j) {
    final label = j['label'];
    final value = j['value'];
    if (label is! String || value is! String) return null;
    final l = label.trim();
    final v = value.trim();
    if (l.isEmpty || v.isEmpty) return null;
    return RegulationField(label: l, value: v);
  }

  /// `regulation_fields` 리스트를 안전 파싱. 누락/형식이상은 빈 리스트로 흡수.
  /// 최대 3개로 제한한다.
  static List<RegulationField> listFromJson(dynamic raw) {
    if (raw is! List) return const [];
    final result = <RegulationField>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final field = RegulationField.tryFromJson(e.cast<String, dynamic>());
      if (field != null) result.add(field);
      if (result.length >= 3) break;
    }
    return result;
  }
}

class TournamentChatCardItem {
  final String id;
  final String title;
  final String sport;
  final String? region;
  final String? location;
  final String startDate;
  final String? endDate;
  final String? applicationDeadline;
  final bool eligible;
  final List<String> eligibleGrades;
  final int? entryFee;
  final String? format;
  final List<RegulationField> regulationFields;

  const TournamentChatCardItem({
    required this.id,
    required this.title,
    required this.sport,
    this.region,
    this.location,
    required this.startDate,
    this.endDate,
    this.applicationDeadline,
    required this.eligible,
    required this.eligibleGrades,
    this.entryFee,
    this.format,
    this.regulationFields = const [],
  });

  /// 필수 필드(id, title, sport, start_date)가 없으면 null 을 반환해 호출자가 건너뛴다.
  static TournamentChatCardItem? tryFromJson(Map<String, dynamic> j) {
    final id = j['id'];
    final title = j['title'];
    final sport = j['sport'];
    final startDate = j['start_date'];
    if (id is! String ||
        title is! String ||
        sport is! String ||
        startDate is! String) {
      return null;
    }
    return TournamentChatCardItem(
      id: id,
      title: title,
      sport: sport,
      region: j['region'] as String?,
      location: j['location'] as String?,
      startDate: startDate,
      endDate: j['end_date'] as String?,
      applicationDeadline: j['application_deadline'] as String?,
      eligible: (j['eligible'] as bool?) ?? false,
      eligibleGrades:
          (j['eligible_grades'] as List?)?.whereType<String>().toList() ??
              const [],
      entryFee: j['entry_fee'] as int?,
      format: j['format'] as String?,
      regulationFields: RegulationField.listFromJson(j['regulation_fields']),
    );
  }
}

class ChatUiBlock {
  final String type; // 'cards'
  final String entity; // 'tournament' | 'club'
  final List<TournamentChatCardItem> tournamentItems;

  const ChatUiBlock({
    required this.type,
    required this.entity,
    required this.tournamentItems,
  });

  /// `ui` 이벤트 data 에서 blocks 리스트를 파싱. 어떤 형식 오류든 빈 리스트로 흡수.
  static List<ChatUiBlock> listFromEvent(Map<String, dynamic> data) {
    final raw = data['blocks'];
    if (raw is! List) return const [];
    final result = <ChatUiBlock>[];
    for (final b in raw) {
      if (b is! Map) continue;
      final block = b.cast<String, dynamic>();
      final entity = block['entity'];
      if (entity is! String) continue;
      final itemsRaw = block['items'];
      final tournamentItems = <TournamentChatCardItem>[];
      if (entity == 'tournament' && itemsRaw is List) {
        for (final it in itemsRaw) {
          if (it is! Map) continue;
          final parsed =
              TournamentChatCardItem.tryFromJson(it.cast<String, dynamic>());
          if (parsed != null) tournamentItems.add(parsed);
        }
      }
      result.add(ChatUiBlock(
        type: (block['type'] as String?) ?? 'cards',
        entity: entity,
        tournamentItems: tournamentItems,
      ));
    }
    return result;
  }
}
