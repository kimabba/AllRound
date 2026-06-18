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
  final String status;
  // Phase 2 신규
  final String? regionCode;
  final List<String> hostAssociations;
  final List<String> hostOrgs;
  final String? divisionLabelLocal;
  final String? divisionKtaStandard;
  final bool isJointEvent;
  final String? futsalEventCategory;

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
    required this.status,
    this.regionCode,
    this.hostAssociations = const [],
    this.hostOrgs = const [],
    this.divisionLabelLocal,
    this.divisionKtaStandard,
    this.isJointEvent = false,
    this.futsalEventCategory,
  });

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
  final String division; // text NOT NULL (PK의 일부)
  final double? score;
  final bool isPrimary;
  final String? regionCode;
  final int? rankingPoints;
  final String? playerOrigin;

  UserTennisOrg({
    required this.org,
    required this.division,
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
    this.status = 'approved',
    this.statusReason,
    this.memberCount = 0,
    this.createdBy,
    this.meetingDays = const [],
    this.monthlyFee,
    this.genderPreference,
    this.createdAt,
    this.myRole,
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isMember => myRole != null;
  bool get isOwner => myRole == 'owner';
  bool get isManager => myRole == 'manager' || myRole == 'owner';

  factory Club.fromJson(Map<String, dynamic> j) {
    // club_members join 결과에서 현재 사용자 role 추출
    final members = j['club_members'] as List?;
    final myMember = members?.isNotEmpty == true ? members!.first : null;
    final myRole = myMember != null && myMember['status'] == 'active'
        ? myMember['role'] as String?
        : null;

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
        title: j['title'] as String,
        body: j['body'] as String,
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
