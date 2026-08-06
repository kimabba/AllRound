enum UgcTargetType {
  clubPost('club_post'),
  clubComment('club_comment'),
  clubEvent('club_event'),
  club('club'),
  user('user'),
  aiMessage('ai_message');

  const UgcTargetType(this.value);
  final String value;
}

enum UgcReportReason {
  abusiveLanguage('abusive_language', '욕설·비속어'),
  spam('spam', '광고·도배'),
  harassment('harassment', '괴롭힘·따돌림'),
  sexualContent('sexual_content', '성적 콘텐츠'),
  hate('hate', '혐오 표현'),
  violence('violence', '폭력·위협'),
  privacy('privacy', '개인정보 노출'),
  other('other', '기타');

  const UgcReportReason(this.value, this.label);
  final String value;
  final String label;

  static UgcReportReason fromValue(String value) => values.firstWhere(
        (reason) => reason.value == value,
        orElse: () => UgcReportReason.other,
      );
}

enum UgcPenaltyType {
  commentRestriction('comment_restriction', '댓글 제한'),
  clubJoinRestriction('club_join_restriction', '클럽 가입 제한'),
  communityRestriction('community_restriction', '커뮤니티 작성 제한');

  const UgcPenaltyType(this.value, this.label);
  final String value;
  final String label;

  static UgcPenaltyType fromValue(String value) => values.firstWhere(
        (type) => type.value == value,
        orElse: () => UgcPenaltyType.communityRestriction,
      );
}

class UgcAccess {
  const UgcAccess({required this.termsAccepted, required this.penalties});

  final bool termsAccepted;
  final List<UserPenalty> penalties;

  factory UgcAccess.fromJson(Map<String, dynamic> json) {
    final rawPenalties = json['penalties'];
    return UgcAccess(
      termsAccepted: json['terms_accepted'] as bool? ?? false,
      penalties: rawPenalties is List
          ? rawPenalties
              .whereType<Map>()
              .map(
                  (row) => UserPenalty.fromJson(Map<String, dynamic>.from(row)))
              .toList(growable: false)
          : const [],
    );
  }
}

class UserPenalty {
  const UserPenalty({
    required this.id,
    required this.type,
    required this.reason,
    this.endsAt,
  });

  final String id;
  final UgcPenaltyType type;
  final String reason;
  final DateTime? endsAt;

  factory UserPenalty.fromJson(Map<String, dynamic> json) => UserPenalty(
        id: json['id'] as String,
        type: UgcPenaltyType.fromValue(json['type'] as String),
        reason: json['reason'] as String? ?? '커뮤니티 운영정책 위반',
        endsAt: DateTime.tryParse(json['ends_at'] as String? ?? ''),
      );

  String get periodLabel {
    final end = endsAt;
    if (end == null) return '영구';
    final local = end.toLocal();
    return '${local.year}.${local.month}.${local.day}까지';
  }
}

class BlockedUser {
  const BlockedUser({
    required this.userId,
    required this.displayName,
    required this.blockedAt,
  });

  final String userId;
  final String displayName;
  final DateTime blockedAt;

  factory BlockedUser.fromJson(Map<String, dynamic> json) => BlockedUser(
        userId: json['user_id'] as String,
        displayName: json['display_name'] as String? ?? '사용자',
        blockedAt: DateTime.parse(json['blocked_at'] as String),
      );
}

class UgcReport {
  const UgcReport({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.reason,
    required this.status,
    required this.evidencePaths,
    required this.snapshot,
    required this.createdAt,
    this.details,
    this.reporterName,
    this.reportedUserId,
    this.reportedUserName,
    this.resolutionNote,
    this.contentDeleted = false,
  });

  final String id;
  final String targetType;
  final String targetId;
  final UgcReportReason reason;
  final String status;
  final String? details;
  final List<String> evidencePaths;
  final Map<String, dynamic> snapshot;
  final DateTime createdAt;
  final String? reporterName;
  final String? reportedUserId;
  final String? reportedUserName;
  final String? resolutionNote;
  final bool contentDeleted;

  factory UgcReport.fromJson(Map<String, dynamic> json) {
    final reporter = _mapFromRelation(json['reporter']);
    final reportedUser = _mapFromRelation(json['reported_user']);
    final evidence = json['evidence_paths'];
    final snapshot = json['content_snapshot'];
    return UgcReport(
      id: json['id'] as String,
      targetType: json['target_type'] as String,
      targetId: json['target_id'] as String,
      reason: UgcReportReason.fromValue(json['reason'] as String),
      status: json['status'] as String,
      details: json['details'] as String?,
      evidencePaths: evidence is List
          ? evidence.whereType<String>().toList(growable: false)
          : const [],
      snapshot: snapshot is Map
          ? Map<String, dynamic>.from(snapshot)
          : const <String, dynamic>{},
      createdAt: DateTime.parse(json['created_at'] as String),
      reporterName: _displayName(reporter),
      reportedUserId: json['reported_user_id'] as String?,
      reportedUserName: _displayName(reportedUser),
      resolutionNote: json['resolution_note'] as String?,
      contentDeleted: json['content_deleted'] as bool? ?? false,
    );
  }

  bool get isOpen => status == 'pending' || status == 'reviewing';
}

Map<String, dynamic>? _mapFromRelation(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is List && value.isNotEmpty && value.first is Map) {
    return Map<String, dynamic>.from(value.first as Map);
  }
  return null;
}

String? _displayName(Map<String, dynamic>? user) {
  if (user == null) return null;
  for (final key in ['nickname', 'name', 'display_name', 'email']) {
    final value = user[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}
