class RecruitingPostPreview {
  const RecruitingPostPreview({
    required this.id,
    required this.clubId,
    required this.sport,
    required this.clubName,
    required this.title,
    required this.region,
    required this.place,
    required this.schedule,
    required this.grade,
    required this.gender,
    required this.age,
    required this.position,
    required this.fieldCount,
    required this.keeperCount,
    required this.totalCount,
    required this.cost,
    required this.createdAt,
    this.intro,
    this.isClosed = false,
    this.closedAt,
  });

  final String id;
  final String clubId;
  final String sport;
  final String clubName;
  final String title;
  final String region;
  final String place;
  final String schedule;
  final String grade;
  final String gender;
  final String age;
  final String? position;
  final int fieldCount;
  final int keeperCount;
  final int totalCount;
  final String cost;
  final String? intro;
  final bool isClosed;
  final DateTime createdAt;
  final DateTime? closedAt;

  String get countLabel {
    if (sport == 'futsal') {
      return '필드 $fieldCount명 · 키퍼 $keeperCount명';
    }
    return '$totalCount명';
  }

  String get introText =>
      intro?.trim().isNotEmpty == true ? intro!.trim() : '자세한 모집 조건을 확인해보세요.';

  factory RecruitingPostPreview.fromJson(Map<String, dynamic> json) {
    final rawClub = json['clubs'];
    final club = rawClub is Map
        ? Map<String, dynamic>.from(rawClub)
        : const <String, dynamic>{};
    final rawCreatedAt = json['created_at'];
    final rawClosedAt = json['closed_at'];
    return RecruitingPostPreview(
      id: json['id'] as String,
      clubId: json['club_id'] as String,
      sport: (club['sport'] as String?) ?? 'tennis',
      clubName: (club['name'] as String?) ?? '클럽',
      title: json['title'] as String,
      region: (club['region'] as String?) ?? '지역 미정',
      place: json['place'] as String,
      schedule: json['schedule_text'] as String,
      grade: json['skill_level'] as String,
      gender: json['gender_text'] as String,
      age: json['age_text'] as String,
      position: json['position_text'] as String?,
      fieldCount: (json['field_count'] as int?) ?? 0,
      keeperCount: (json['keeper_count'] as int?) ?? 0,
      totalCount: (json['total_count'] as int?) ?? 1,
      cost: (json['cost_text'] as String?) ?? '협의',
      intro: json['intro'] as String?,
      isClosed: json['status'] == 'closed',
      createdAt: rawCreatedAt is String
          ? DateTime.tryParse(rawCreatedAt) ??
              DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime.fromMillisecondsSinceEpoch(0),
      closedAt: rawClosedAt is String ? DateTime.tryParse(rawClosedAt) : null,
    );
  }
}
