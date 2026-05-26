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
  });

  factory Tournament.fromJson(Map<String, dynamic> j) {
    final grades = (j['eligible_grades'] as List?)?.cast<String>() ?? const [];
    final hostAssoc =
        (j['host_associations'] as List?)?.cast<String>() ?? const [];
    final hostOrgs = (j['host_orgs'] as List?)?.cast<String>() ?? const [];
    return Tournament(
      id: j['id'] as String,
      sport: j['sport'] as String,
      title: j['title'] as String,
      organizer: j['organizer'] as String?,
      description: j['description'] as String?,
      startDate: DateTime.parse(j['start_date'] as String),
      endDate:
          j['end_date'] != null ? DateTime.parse(j['end_date'] as String) : null,
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
      divisionLabelLocal: j['division_label_local'] as String?,
      divisionKtaStandard: j['division_kta_standard'] as String?,
      isJointEvent: (j['is_joint_event'] as bool?) ?? false,
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
  final String? divisionLocal;
  final double? score; // 1.0~10.0 (KTA) / 1~9 (제주)
  final DateTime? expiresAt;
  final bool isPrimary;
  final String? regionCode;

  UserTennisOrg({
    required this.org,
    this.divisionLocal,
    this.score,
    this.expiresAt,
    this.isPrimary = false,
    this.regionCode,
  });

  factory UserTennisOrg.fromJson(Map<String, dynamic> j) {
    final scoreVal = j['score'];
    final double? score = scoreVal == null
        ? null
        : (scoreVal is num ? scoreVal.toDouble() : double.tryParse('$scoreVal'));
    return UserTennisOrg(
      org: j['org'] as String,
      divisionLocal: j['division_local'] as String?,
      score: score,
      expiresAt: j['expires_at'] != null
          ? DateTime.parse(j['expires_at'] as String)
          : null,
      isPrimary: (j['is_primary'] as bool?) ?? false,
      regionCode: j['region_code'] as String?,
    );
  }

  Map<String, dynamic> toUpsert(String userId) => {
        'user_id': userId,
        'org': org,
        'division_local': divisionLocal,
        'score': score,
        'expires_at': expiresAt?.toIso8601String().substring(0, 10),
        'is_primary': isPrimary,
        'region_code': regionCode,
      };
}

class Club {
  final String id;
  final String sport;
  final String name;
  final String? region;
  final String? address;
  final String? contact;
  final String? website;
  final String? description;
  final String status; // 'pending' | 'approved' | 'rejected'
  final String? statusReason;
  final int memberCount;
  final String? createdBy;
  // 현재 사용자의 멤버십 정보 (조회 시 join)
  final String? myRole; // 'owner'|'manager'|'member'|null

  Club({
    required this.id,
    required this.sport,
    required this.name,
    this.region,
    this.address,
    this.contact,
    this.website,
    this.description,
    this.status = 'approved',
    this.statusReason,
    this.memberCount = 0,
    this.createdBy,
    this.myRole,
  });

  bool get isPending  => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isMember   => myRole != null;
  bool get isOwner    => myRole == 'owner';
  bool get isManager  => myRole == 'manager' || myRole == 'owner';

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
      contact: j['contact'] as String?,
      website: j['website'] as String?,
      description: j['description'] as String?,
      status: (j['status'] as String?) ?? 'approved',
      statusReason: j['status_reason'] as String?,
      memberCount: (j['member_count'] as int?) ?? 0,
      createdBy: j['created_by'] as String?,
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

  RuleArticle({
    required this.id,
    required this.sport,
    required this.category,
    required this.title,
    required this.body,
  });

  factory RuleArticle.fromJson(Map<String, dynamic> j) => RuleArticle(
        id: j['id'] as String,
        sport: j['sport'] as String,
        category: j['category'] as String,
        title: j['title'] as String,
        body: j['body'] as String,
      );
}

class UserSport {
  final String sport;   // 'tennis' / 'futsal'
  final String grade;   // 'div3' / 'intermediate' 등
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
