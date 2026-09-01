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

  /// 이미 끝난 대회인가. **서버(KST)가 판정한 값**이고, 판정할 수 없었으면 null.
  ///
  /// 날짜를 앱에서 계산하지 않는 이유가 둘이다.
  ///  1) end_date 없는 행이 대다수인데(단일일 대회) 그 null 과, RAG 경로처럼
  ///     종료일을 조회하지 못한 null 은 뜻이 다르다. 그 구분은 행의 출처를 아는
  ///     서버만 할 수 있다(_shared/chat_cards.ts).
  ///  2) 기기 시계를 쓰면 한국 자정 근처에서 서버 판정과 하루 어긋난다.
  ///
  /// 필드가 없는 응답(배포 전 서버)이면 null 이라 배지를 띄우지 않는다 — 잘못
  /// 표시하느니 표시하지 않는다.
  final bool? finished;

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
    this.finished,
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
      finished: j['finished'] as bool?,
    );
  }
}

class ClubChatCardItem {
  final String id;
  final String name;
  final String sport;
  final String? region;
  final String? description;
  final int memberCount;
  final int? monthlyFee;
  final String feeType;
  final List<String> meetingDays;
  final String? genderPreference;

  const ClubChatCardItem({
    required this.id,
    required this.name,
    required this.sport,
    this.region,
    this.description,
    required this.memberCount,
    this.monthlyFee,
    this.feeType = 'monthly',
    this.meetingDays = const [],
    this.genderPreference,
  });

  /// 필수 필드(id, name, sport)가 없으면 null 을 반환해 호출자가 건너뛴다.
  static ClubChatCardItem? tryFromJson(Map<String, dynamic> j) {
    final id = j['id'];
    final name = j['name'];
    final sport = j['sport'];
    if (id is! String || name is! String || sport is! String) return null;
    return ClubChatCardItem(
      id: id,
      name: name,
      sport: sport,
      region: j['region'] as String?,
      description: j['description'] as String?,
      memberCount: (j['member_count'] as int?) ?? 0,
      monthlyFee: j['monthly_fee'] as int?,
      feeType: j['fee_type'] == 'per_event' ? 'per_event' : 'monthly',
      meetingDays: (j['meeting_days'] as List?)?.whereType<String>().toList() ??
          const [],
      genderPreference: j['gender_preference'] as String?,
    );
  }
}

/// 대회검색 결과에 붙는 "내 등급만 보기"/"전체 대회 보기" 정제 칩(JY-101).
/// refine 페이로드를 그대로 다음 chat 요청의 tournament_refine 으로 되돌려보낸다.
class RefineChip {
  final String label;
  final Map<String, dynamic> refine;
  const RefineChip({required this.label, required this.refine});

  static RefineChip? tryFromJson(Map<String, dynamic> j) {
    final label = j['label'];
    final refine = j['refine'];
    if (label is! String || refine is! Map) return null;
    return RefineChip(label: label, refine: refine.cast<String, dynamic>());
  }
}

class ChatUiBlock {
  final String type; // 'cards'
  final String entity; // 'tournament' | 'club'
  final List<TournamentChatCardItem> tournamentItems;
  final List<ClubChatCardItem> clubItems;
  final RefineChip? refineChip;

  const ChatUiBlock({
    required this.type,
    required this.entity,
    required this.tournamentItems,
    this.clubItems = const [],
    this.refineChip,
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
      final clubItems = <ClubChatCardItem>[];
      if (itemsRaw is List) {
        for (final it in itemsRaw) {
          if (it is! Map) continue;
          final json = it.cast<String, dynamic>();
          if (entity == 'tournament') {
            final parsed = TournamentChatCardItem.tryFromJson(json);
            if (parsed != null) tournamentItems.add(parsed);
          } else if (entity == 'club') {
            final parsed = ClubChatCardItem.tryFromJson(json);
            if (parsed != null) clubItems.add(parsed);
          }
        }
      }
      final refineRaw = block['refine_chip'];
      final refineChip = refineRaw is Map
          ? RefineChip.tryFromJson(refineRaw.cast<String, dynamic>())
          : null;
      result.add(ChatUiBlock(
        type: (block['type'] as String?) ?? 'cards',
        entity: entity,
        tournamentItems: tournamentItems,
        clubItems: clubItems,
        refineChip: refineChip,
      ));
    }
    return result;
  }
}
