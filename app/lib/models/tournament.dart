/// 대회 요강 AI 정형화 처리 상태 (관리자 전용, 유저 노출 없음).
enum FormatStatus {
  pending,
  processing,
  formatted,
  needsReview,
  failed,
  skipped;

  static FormatStatus fromString(String? s) {
    switch (s) {
      case 'processing':
        return FormatStatus.processing;
      case 'formatted':
        return FormatStatus.formatted;
      case 'needs_review':
        return FormatStatus.needsReview;
      case 'failed':
        return FormatStatus.failed;
      case 'skipped':
        return FormatStatus.skipped;
      case 'pending':
      default:
        return FormatStatus.pending;
    }
  }
}

/// 대회 요강 정형 필드 한 줄 (라벨:값). 마이그레이션 073 의
/// regulation_fields jsonb 배열 [{"label", "value"}] 한 요소에 대응한다.
class RegulationField {
  final String label;
  final String value;

  const RegulationField({required this.label, required this.value});

  /// JSON 경계에서만 dynamic 을 받아 즉시 String 으로 안전 변환한다.
  static RegulationField? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final label = raw['label'];
    final value = raw['value'];
    if (label is! String) return null;
    final labelStr = label.trim();
    if (labelStr.isEmpty) return null;
    final valueStr = value is String ? value.trim() : '';
    return RegulationField(label: labelStr, value: valueStr);
  }
}

class Tournament {
  final String id;
  final String sport;
  final String title;
  final String? organizer;
  final String? description;
  final DateTime startDate;
  final DateTime? endDate;
  final DateTime? applicationDeadline;
  final String? region;
  final String? location;
  final List<String> eligibleGrades;
  final int? entryFee;
  final String entryFeeUnit; // 'per_team' | 'per_person'
  final String? prize;
  final String? format;
  final String? sourceUrl;
  final String? posterUrl;
  final String status;
  // Phase 2 신규
  final String? regionCode;
  final List<String> hostAssociations;
  final List<String> hostOrgs;
  final String? divisionLabelLocal;
  final String? divisionKtaStandard;
  final bool isJointEvent;
  final String? futsalEventCategory;
  // 마이그레이션 073: 구조화 요강
  final List<RegulationField> regulationFields;
  final List<String> regulationNotes;
  // 마이그레이션 074: 읽기 쉬운 완전 본문 (여러 줄, "\n" 보존)
  final String? regulationBody;
  // AI 정형화 파이프라인 처리 상태 (관리자 전용)
  final FormatStatus formatStatus;

  Tournament({
    required this.id,
    required this.sport,
    required this.title,
    this.organizer,
    this.description,
    required this.startDate,
    this.endDate,
    this.applicationDeadline,
    this.region,
    this.location,
    required this.eligibleGrades,
    this.entryFee,
    this.entryFeeUnit = 'per_team',
    this.prize,
    this.format,
    this.sourceUrl,
    this.posterUrl,
    required this.status,
    this.regionCode,
    this.hostAssociations = const [],
    this.hostOrgs = const [],
    this.divisionLabelLocal,
    this.divisionKtaStandard,
    this.isJointEvent = false,
    this.futsalEventCategory,
    this.regulationFields = const [],
    this.regulationNotes = const [],
    this.regulationBody,
    this.formatStatus = FormatStatus.pending,
  });

  /// 접수 마감 여부 공용 판정. 상태칩·신청바·카드가 같은 기준을 쓰도록 단일화한다.
  /// 기준: closed/cancelled 이거나, 신청 마감일이 지났거나,
  /// (마감일이 없으면) published 인데 대회 시작일이 지난 경우.
  bool get isRegistrationClosed {
    if (status == 'closed' || status == 'cancelled') return true;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (applicationDeadline != null) {
      return applicationDeadline!.difference(today).inDays < 0;
    }
    return status == 'published' && startDate.isBefore(today);
  }

  factory Tournament.fromJson(Map<String, dynamic> j) {
    // 확장 테이블 데이터 (JOIN 시 nested, RPC 시 flat — 둘 다 호환)
    final tennis = j['tennis_tournament_details'] as Map<String, dynamic>?;
    final futsal = j['futsal_tournament_details'] as Map<String, dynamic>?;
    final ext = tennis ?? futsal;

    final grades = (j['eligible_grades'] as List?)?.cast<String>() ?? const [];
    final hostAssoc = (ext?['host_associations'] as List?)?.cast<String>() ??
        (j['host_associations'] as List?)?.cast<String>() ??
        const [];
    final hostOrgs = (ext?['host_orgs'] as List?)?.cast<String>() ??
        (j['host_orgs'] as List?)?.cast<String>() ??
        const [];

    // regulation_fields: List<dynamic> of Map → List<RegulationField>
    final rawFields = j['regulation_fields'];
    final regulationFields = rawFields is List
        ? rawFields
            .map(RegulationField.tryFromJson)
            .whereType<RegulationField>()
            .toList(growable: false)
        : const <RegulationField>[];
    String? structuredPosterUrl;
    for (final field in regulationFields) {
      final value = field.value.trim();
      if (field.label.replaceAll(' ', '') == '포스터' &&
          (value.startsWith('https://') || value.startsWith('http://'))) {
        structuredPosterUrl = value;
        break;
      }
    }

    // regulation_notes: List<dynamic> → List<String> (빈/비문자열 제거)
    final rawNotes = j['regulation_notes'];
    final regulationNotes = rawNotes is List
        ? rawNotes
            .whereType<String>()
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(growable: false)
        : const <String>[];

    // regulation_body: 여러 줄 문자열. 비문자열/빈 문자열이면 null.
    final rawBody = j['regulation_body'];
    final regulationBody =
        rawBody is String && rawBody.trim().isNotEmpty ? rawBody : null;

    return Tournament(
      id: j['id'] as String,
      sport: j['sport'] as String,
      title: j['title'] as String,
      organizer: j['organizer'] as String?,
      description: j['description'] as String?,
      startDate: DateTime.parse(j['start_date'] as String),
      endDate: j['end_date'] != null
          ? DateTime.parse(j['end_date'] as String)
          : null,
      applicationDeadline: j['application_deadline'] != null
          ? DateTime.parse(j['application_deadline'] as String)
          : null,
      region: j['region'] as String?,
      location: j['location'] as String?,
      eligibleGrades: grades,
      entryFee: j['entry_fee'] as int?,
      entryFeeUnit: (j['entry_fee_unit'] as String?) ?? 'per_team',
      prize: j['prize'] as String?,
      format: j['format'] as String?,
      sourceUrl: j['source_url'] as String?,
      posterUrl: (j['poster_url'] as String?) ?? structuredPosterUrl,
      status: j['status'] as String,
      regionCode: j['region_code'] as String?,
      hostAssociations: hostAssoc,
      hostOrgs: hostOrgs,
      divisionLabelLocal: ext?['division_label_local'] as String? ??
          j['division_label_local'] as String?,
      divisionKtaStandard: ext?['division_kta_standard'] as String? ??
          j['division_kta_standard'] as String?,
      isJointEvent: ext?['is_joint_event'] as bool? ??
          j['is_joint_event'] as bool? ??
          false,
      futsalEventCategory: ext?['event_category'] as String? ??
          j['futsal_event_category'] as String? ??
          j['event_category'] as String?,
      regulationFields: regulationFields,
      regulationNotes: regulationNotes,
      regulationBody: regulationBody,
      formatStatus: FormatStatus.fromString(j['format_status'] as String?),
    );
  }
}

class Region {
  final String code;
  final String displayNameKo;
  final List<String> governingAssociations;
  final bool usesKato;
  final bool usesKata;
  final String? notes;

  Region({
    required this.code,
    required this.displayNameKo,
    this.governingAssociations = const [],
    this.usesKato = false,
    this.usesKata = false,
    this.notes,
  });

  factory Region.fromJson(Map<String, dynamic> j) => Region(
        code: j['code'] as String,
        displayNameKo: j['display_name_ko'] as String,
        governingAssociations:
            (j['governing_associations'] as List?)?.cast<String>() ?? const [],
        usesKato: (j['uses_kato'] as bool?) ?? false,
        usesKata: (j['uses_kata'] as bool?) ?? false,
        notes: j['notes'] as String?,
      );
}

class UserTennisOrg {
  final String org; // 'kta'|'kato'|...|'gj'|'jn'|'local'
  final String division; // text NOT NULL (PK의 일부) — 표시용 라벨
  final List<String> divisionCodes; // 자격매칭용 카탈로그 코드 (JY-136)
  final double? score;
  final bool isPrimary;
  final String? regionCode;
  final int? rankingPoints;
  final String? playerOrigin;

  UserTennisOrg({
    required this.org,
    required this.division,
    this.divisionCodes = const [],
    this.score,
    this.isPrimary = false,
    this.regionCode,
    this.rankingPoints,
    this.playerOrigin,
  });

  factory UserTennisOrg.fromJson(Map<String, dynamic> j) {
    final scoreVal = j['score'];
    final double? score = scoreVal == null
        ? null
        : (scoreVal is num
            ? scoreVal.toDouble()
            : double.tryParse('$scoreVal'));
    return UserTennisOrg(
      org: j['org'] as String,
      division: j['division'] as String,
      divisionCodes:
          (j['division_codes'] as List?)?.map((e) => e as String).toList() ??
              const [],
      score: score,
      isPrimary: (j['is_primary'] as bool?) ?? false,
      regionCode: j['region_code'] as String?,
      rankingPoints: j['ranking_points'] as int?,
      playerOrigin: j['player_origin'] as String?,
    );
  }

  Map<String, dynamic> toUpsert(String userId) => {
        'user_id': userId,
        'org': org,
        'division': division,
        'division_codes': divisionCodes,
        'score': score,
        'is_primary': isPrimary,
        'region_code': regionCode,
        'ranking_points': rankingPoints,
        'player_origin': playerOrigin,
      };
}

class Club {
  final String id;
  final String sport;
  final String name;
  final String? region;
  final String? address;
  final String? logoUrl;
  final String? contact;
  final String? website;
  final String? description;
  final List<String> introImageUrls;
  final String status; // 'pending' | 'approved' | 'rejected'
  final String? statusReason;
  final int memberCount;
  final String? createdBy;
  final List<String> meetingDays;
  final int? monthlyFee;
  final String? genderPreference;
  final DateTime? createdAt;
  // 현재 사용자의 멤버십 정보 (조회 시 join)
  final String? myRole; // 'owner'|'manager'|'member'|null
  final bool myCanPostNotice;

  Club({
    required this.id,
    required this.sport,
    required this.name,
    this.region,
    this.address,
    this.logoUrl,
    this.contact,
    this.website,
    this.description,
    this.introImageUrls = const [],
    this.status = 'approved',
    this.statusReason,
    this.memberCount = 0,
    this.createdBy,
    this.meetingDays = const [],
    this.monthlyFee,
    this.genderPreference,
    this.createdAt,
    this.myRole,
    this.myCanPostNotice = false,
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isMember => myRole != null;
  bool get isOwner => myRole == 'owner';
  bool get isManager => myRole == 'manager' || myRole == 'owner';
  bool get canPostNotice => isManager || myCanPostNotice;

  factory Club.fromJson(Map<String, dynamic> j) {
    // club_members join 결과에서 현재 사용자 role 추출
    final members = j['club_members'] as List?;
    final myMember = members?.isNotEmpty == true ? members!.first : null;
    final myRole = myMember != null && myMember['status'] == 'active'
        ? myMember['role'] as String?
        : null;
    final myCanPostNotice = myMember != null && myMember['status'] == 'active'
        ? (myMember['can_post_notice'] as bool?) ?? false
        : false;

    return Club(
      id: j['id'] as String,
      sport: j['sport'] as String,
      name: j['name'] as String,
      region: j['region'] as String?,
      address: j['address'] as String?,
      logoUrl: j['logo_url'] as String?,
      contact: j['contact'] as String?,
      website: j['website'] as String?,
      description: j['description'] as String?,
      introImageUrls:
          (j['intro_image_urls'] as List?)?.cast<String>() ?? const [],
      status: (j['status'] as String?) ?? 'approved',
      statusReason: j['status_reason'] as String?,
      memberCount: (j['member_count'] as int?) ?? 0,
      createdBy: j['created_by'] as String?,
      meetingDays: (j['meeting_days'] as List?)?.cast<String>() ?? const [],
      monthlyFee: j['monthly_fee'] as int?,
      genderPreference: j['gender_preference'] as String?,
      createdAt: j['created_at'] != null
          ? DateTime.parse(j['created_at'] as String)
          : null,
      myRole: myRole,
      myCanPostNotice: myCanPostNotice,
    );
  }
}

class RuleArticle {
  final String id;
  final String sport;
  final String category;
  final String title;
  final String body;
  final int orderIdx;
  final bool published;
  final DateTime? embeddingUpdatedAt;
  final DateTime? updatedAt;

  RuleArticle({
    required this.id,
    required this.sport,
    required this.category,
    required this.title,
    required this.body,
    this.orderIdx = 0,
    this.published = true,
    this.embeddingUpdatedAt,
    this.updatedAt,
  });

  /// embedding_updated_at 이 null 이면 임베딩 대기(재계산 필요), 아니면 최신.
  bool get embeddingPending => embeddingUpdatedAt == null;

  factory RuleArticle.fromJson(Map<String, dynamic> j) => RuleArticle(
        id: j['id'] as String,
        sport: j['sport'] as String,
        category: j['category'] as String,
        title: normalizeRuleTitle(j['title'] as String),
        body: normalizeRuleBody(j['body'] as String),
        orderIdx: (j['order_idx'] as int?) ?? 0,
        published: (j['published'] as bool?) ?? true,
        embeddingUpdatedAt: j['embedding_updated_at'] != null
            ? DateTime.parse(j['embedding_updated_at'] as String)
            : null,
        updatedAt: j['updated_at'] != null
            ? DateTime.parse(j['updated_at'] as String)
            : null,
      );
}

String normalizeRuleTitle(String title) {
  return title.replaceFirst(RegExp(r'^\s*규칙\s*\d+\s*[–—-]\s*'), '').trim();
}

String normalizeRuleBody(String body) {
  return body
      .replaceAll(r'\r\n', '\n')
      .replaceAll(r'\n', '\n')
      .replaceAll('|n', '\n');
}

class UserSport {
  final String sport; // 'tennis' / 'futsal'
  final String grade; // 'div3' / 'intermediate' 등
  final bool isPrimary;

  UserSport({required this.sport, required this.grade, this.isPrimary = false});

  factory UserSport.fromJson(Map<String, dynamic> j) => UserSport(
        sport: j['sport'] as String,
        grade: j['grade'] as String,
        isPrimary: j['is_primary'] as bool? ?? false,
      );

  Map<String, dynamic> toInsert(String userId) => {
        'user_id': userId,
        'sport': sport,
        'grade': grade,
        'is_primary': isPrimary,
      };
}

/// 본인 프로필. name=실명(대회·클럽), nickname=앱 활동명, birthDate=비공개 매칭용,
/// primaryRegion=활동 지역 코드(users.primary_region, 유저 지역의 단일 진실원천).
class UserProfile {
  final String? name;
  final String? nickname;
  final DateTime? birthDate;
  final String? primaryRegion;
  final String? avatarUrl;
  final DateTime? phoneVerifiedAt;

  const UserProfile({
    this.name,
    this.nickname,
    this.birthDate,
    this.primaryRegion,
    this.avatarUrl,
    this.phoneVerifiedAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        name: j['name'] as String?,
        nickname: j['nickname'] as String?,
        birthDate: j['birth_date'] == null
            ? null
            : DateTime.tryParse(j['birth_date'] as String),
        primaryRegion: j['primary_region'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        phoneVerifiedAt: j['phone_verified_at'] == null
            ? null
            : DateTime.tryParse(j['phone_verified_at'] as String),
      );

  /// 앱 활동 표시명: 닉네임 우선, 없으면 실명. 둘 다 없으면 null.
  String? get displayName {
    final n = nickname?.trim();
    if (n != null && n.isNotEmpty) return n;
    final r = name?.trim();
    if (r != null && r.isNotEmpty) return r;
    return null;
  }

  /// 만 나이 (기준일 now). 생년월일 없으면 null.
  int? ageOn(DateTime now) {
    final b = birthDate;
    if (b == null) return null;
    var age = now.year - b.year;
    if (now.month < b.month || (now.month == b.month && now.day < b.day)) {
      age--;
    }
    return age;
  }
}

class ChatMessage {
  final String id;
  final String role; // 'user' | 'assistant'
  final String content;
  final List<dynamic> citations;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.citations,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        role: j['role'] as String,
        content: j['content'] as String,
        citations: (j['citations'] as List?) ?? const [],
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}
