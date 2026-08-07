class ClubInquiryThread {
  const ClubInquiryThread({
    required this.id,
    required this.clubId,
    required this.requesterId,
    required this.status,
    required this.lastMessageAt,
    required this.createdAt,
    this.requesterNickname,
    this.requesterAvatarUrl,
    this.requesterRegion,
    this.requesterAgeGroup,
    this.requesterSports = const [],
    this.requesterTeams = const [],
    this.requesterTournaments = const [],
    this.requesterTennisOrganizations = const [],
  });

  final String id;
  final String clubId;
  final String requesterId;
  final String status;
  final DateTime lastMessageAt;
  final DateTime createdAt;
  final String? requesterNickname;
  final String? requesterAvatarUrl;
  final String? requesterRegion;
  final String? requesterAgeGroup;
  final List<String> requesterSports;
  final List<String> requesterTeams;
  final List<String> requesterTournaments;
  final List<String> requesterTennisOrganizations;

  String get requesterLabel {
    final nickname = requesterNickname?.trim();
    return nickname == null || nickname.isEmpty ? '문의자' : nickname;
  }

  factory ClubInquiryThread.fromJson(Map<String, dynamic> json) {
    final requester = json['requester'];
    final requesterMap = requester is Map
        ? Map<String, dynamic>.from(requester)
        : const <String, dynamic>{};
    return ClubInquiryThread(
      id: json['id'] as String,
      clubId: json['club_id'] as String,
      requesterId: json['requester_id'] as String,
      status: (json['status'] as String?) ?? 'open',
      lastMessageAt: DateTime.parse(json['last_message_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      requesterNickname: requesterMap['nickname'] as String?,
      requesterAvatarUrl: requesterMap['avatar_url'] as String?,
      requesterRegion: requesterMap['primary_region'] as String?,
      requesterAgeGroup: requesterMap['age_group'] as String?,
      requesterSports: (requesterMap['sports'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => '${row['sport'] ?? ''}:${row['grade'] ?? ''}')
          .toList(growable: false),
      requesterTeams: (requesterMap['clubs'] as List? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      requesterTournaments: (requesterMap['tournaments'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => '${row['title'] ?? '대회'} · ${row['division'] ?? ''}')
          .toList(growable: false),
      requesterTennisOrganizations:
          (requesterMap['tennis_orgs'] as List? ?? const [])
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

class ClubInquiryMessage {
  const ClubInquiryMessage({
    required this.id,
    required this.threadId,
    required this.senderId,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String threadId;
  final String? senderId;
  final String body;
  final DateTime createdAt;

  factory ClubInquiryMessage.fromJson(Map<String, dynamic> json) =>
      ClubInquiryMessage(
        id: json['id'] as String,
        threadId: json['thread_id'] as String,
        senderId: json['sender_id'] as String?,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
