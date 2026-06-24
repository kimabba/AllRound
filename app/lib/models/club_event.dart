// 클럽 활동 MVP 모델: 모임 일정 + 멤버

class ClubMember {
  final String userId;
  final String role; // 'owner' | 'manager' | 'member'
  final bool canCreateEvent;
  final bool canPostNotice;
  final String? displayName;
  final DateTime? joinedAt;

  ClubMember({
    required this.userId,
    required this.role,
    this.canCreateEvent = false,
    this.canPostNotice = false,
    this.displayName,
    this.joinedAt,
  });

  bool get isOwner => role == 'owner';
  bool get isManager => role == 'manager';

  String get roleLabel => switch (role) {
        'owner' => '클럽장',
        'manager' => '운영진',
        _ => '멤버',
      };

  factory ClubMember.fromJson(Map<String, dynamic> j) {
    final user = j['users'] as Map<String, dynamic>?;
    return ClubMember(
      userId: j['user_id'] as String,
      role: (j['role'] as String?) ?? 'member',
      canCreateEvent: (j['can_create_event'] as bool?) ?? false,
      canPostNotice: (j['can_post_notice'] as bool?) ?? false,
      displayName: user?['name'] as String?,
      joinedAt: j['joined_at'] != null
          ? DateTime.tryParse(j['joined_at'] as String)
          : null,
    );
  }
}

class ClubEvent {
  final String id;
  final String clubId;
  final String? createdBy; // 작성자 탈퇴 시 067 FK 에 의해 NULL 가능
  final String title;
  final String? description;
  final String? locationText;
  final DateTime startsAt;
  final int goingCount;
  final String? myStatus; // 'going' | 'not_going' | null

  ClubEvent({
    required this.id,
    required this.clubId,
    this.createdBy,
    required this.title,
    this.description,
    this.locationText,
    required this.startsAt,
    this.goingCount = 0,
    this.myStatus,
  });

  bool get iAmGoing => myStatus == 'going';

  factory ClubEvent.fromJson(
    Map<String, dynamic> j, {
    required String? currentUserId,
  }) {
    final attendees = (j['club_event_attendees'] as List?) ?? const [];
    var going = 0;
    String? myStatus;
    for (final a in attendees) {
      final m = a as Map<String, dynamic>;
      if (m['status'] == 'going') going++;
      if (currentUserId != null && m['user_id'] == currentUserId) {
        myStatus = m['status'] as String?;
      }
    }
    return ClubEvent(
      id: j['id'] as String,
      clubId: j['club_id'] as String,
      createdBy: j['created_by'] as String?,
      title: j['title'] as String,
      description: j['description'] as String?,
      locationText: j['location_text'] as String?,
      startsAt: DateTime.parse(j['starts_at'] as String),
      goingCount: going,
      myStatus: myStatus,
    );
  }
}
