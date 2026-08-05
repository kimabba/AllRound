// 클럽 활동 MVP 모델: 가입 신청 + 모임(정기·번개) + 멤버

class MyClubJoinRequest {
  const MyClubJoinRequest({
    required this.id,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String status;
  final DateTime? createdAt;

  bool get isPending => status == 'pending';

  factory MyClubJoinRequest.fromJson(Map<String, dynamic> json) {
    final rawCreatedAt = json['created_at'];
    return MyClubJoinRequest(
      id: json['id'] as String,
      status: (json['status'] as String?) ?? 'pending',
      createdAt:
          rawCreatedAt is String ? DateTime.tryParse(rawCreatedAt) : null,
    );
  }
}

class ClubMember {
  final String userId;
  final String role; // 'owner' | 'manager' | 'member'
  final bool canCreateEvent;
  final bool canPostNotice;
  final String? displayName;
  final String? avatarUrl;
  final DateTime? joinedAt;
  final List<String> sports;
  final List<String> teams;
  final List<String> tournaments;
  final List<String> tennisOrganizations;

  ClubMember({
    required this.userId,
    required this.role,
    this.canCreateEvent = false,
    this.canPostNotice = false,
    this.displayName,
    this.avatarUrl,
    this.joinedAt,
    this.sports = const [],
    this.teams = const [],
    this.tournaments = const [],
    this.tennisOrganizations = const [],
  });

  bool get isOwner => role == 'owner';
  bool get isManager => role == 'manager';

  String get roleLabel => switch (role) {
        'owner' => '클럽장',
        'manager' => '운영진',
        _ => '멤버',
      };

  factory ClubMember.fromJson(Map<String, dynamic> j) {
    final rawUser = j['users'];
    final user = rawUser is Map
        ? Map<String, dynamic>.from(rawUser)
        : rawUser is List && rawUser.isNotEmpty && rawUser.first is Map
            ? Map<String, dynamic>.from(rawUser.first as Map)
            : null;
    return ClubMember(
      userId: j['user_id'] as String,
      role: (j['role'] as String?) ?? 'member',
      canCreateEvent: (j['can_create_event'] as bool?) ?? false,
      canPostNotice: (j['can_post_notice'] as bool?) ?? false,
      displayName: (user?['nickname'] as String?) ?? user?['name'] as String?,
      avatarUrl: user?['avatar_url'] as String?,
      joinedAt: j['joined_at'] != null
          ? DateTime.tryParse(j['joined_at'] as String)
          : null,
      sports: (user?['sports'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => '${row['sport'] ?? ''}:${row['grade'] ?? ''}')
          .toList(growable: false),
      teams: (user?['clubs'] as List? ?? const []).whereType<String>().toList(),
      tournaments: (user?['tournaments'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => '${row['title'] ?? '대회'} · ${row['division'] ?? ''}')
          .toList(growable: false),
      tennisOrganizations: (user?['tennis_orgs'] as List? ?? const [])
          .whereType<Map>()
          .map((row) {
        final details = [row['division'], row['score']]
            .where((value) => value != null && '$value'.isNotEmpty)
            .join(' · ');
        return details.isEmpty
            ? '${row['org'] ?? ''}'
            : '${row['org'] ?? ''} · $details';
      }).toList(growable: false),
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
  final DateTime? endedEarlyAt;
  final String? repeatInterval;
  final int? fee;
  final int? capacity;
  final int goingCount;
  final int notGoingCount;
  final String? myStatus; // 'going' | 'not_going' | null
  final List<ClubEventAttendance> attendees;

  ClubEvent({
    required this.id,
    required this.clubId,
    this.createdBy,
    required this.title,
    this.description,
    this.locationText,
    required this.startsAt,
    this.endedEarlyAt,
    this.repeatInterval,
    this.fee,
    this.capacity,
    this.goingCount = 0,
    this.notGoingCount = 0,
    this.myStatus,
    this.attendees = const [],
  });

  bool get iAmGoing => myStatus == 'going';
  bool get iAmNotGoing => myStatus == 'not_going';
  int get responseCount => goingCount + notGoingCount;
  bool get isFull => capacity != null && goingCount >= capacity!;
  bool get isEndedEarly => endedEarlyAt != null;
  String? get repeatLabel => switch (repeatInterval) {
        'weekly' => '매주',
        'monthly' => '매월',
        _ => null,
      };

  factory ClubEvent.fromJson(
    Map<String, dynamic> j, {
    required String? currentUserId,
  }) {
    final attendeeRows = (j['club_event_attendees'] as List?) ?? const [];
    final parsedAttendees = <ClubEventAttendance>[];
    var going = 0;
    var notGoing = 0;
    String? myStatus;
    for (final a in attendeeRows) {
      final m = a as Map<String, dynamic>;
      final attendee = ClubEventAttendance.fromJson(m);
      parsedAttendees.add(attendee);
      if (attendee.status == 'going') {
        going++;
      } else if (attendee.status == 'not_going') {
        notGoing++;
      }
      if (currentUserId != null && m['user_id'] == currentUserId) {
        myStatus = attendee.status;
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
      endedEarlyAt: j['ended_early_at'] is String
          ? DateTime.tryParse(j['ended_early_at'] as String)
          : null,
      repeatInterval: j['repeat_interval'] as String?,
      fee: j['fee'] as int?,
      capacity: j['capacity'] as int?,
      goingCount: going,
      notGoingCount: notGoing,
      myStatus: myStatus,
      attendees: parsedAttendees,
    );
  }
}

class ClubEventAttendance {
  final String userId;
  final String status; // 'going' | 'not_going'

  const ClubEventAttendance({
    required this.userId,
    required this.status,
  });

  bool get isGoing => status == 'going';
  bool get isNotGoing => status == 'not_going';

  factory ClubEventAttendance.fromJson(Map<String, dynamic> j) {
    return ClubEventAttendance(
      userId: j['user_id'] as String,
      status: (j['status'] as String?) ?? 'not_going',
    );
  }
}
