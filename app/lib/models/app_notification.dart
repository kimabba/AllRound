class AppNotification {
  final String id;
  final String type;
  final String title;
  final String? body;
  final String? referenceType;
  final String? referenceId;
  final String? clubId;
  final bool isRead;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    this.body,
    this.referenceType,
    this.referenceId,
    this.clubId,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
    id: j['id'] as String,
    type: j['type'] as String,
    title: j['title'] as String,
    body: j['body'] as String?,
    referenceType: j['reference_type'] as String?,
    referenceId: j['reference_id'] as String?,
    clubId: j['club_id'] as String?,
    isRead: (j['is_read'] as bool?) ?? false,
    createdAt: DateTime.parse(j['created_at'] as String),
  );

  String get typeLabel => switch (type) {
    'tournament_d3' => '대회 D-3',
    'tournament_deadline' => '신청 마감',
    'club_notice' => '클럽 공지',
    'club_event' => '클럽 일정',
    'club_mention' => '멘션',
    'club_comment' => '댓글',
    'club_event_reminder' => '일정 리마인더',
    'club_attendance_change' => '참석 변경',
    _ => type,
  };
}
