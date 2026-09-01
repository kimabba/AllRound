import 'dart:async';

class NotificationEvent {
  const NotificationEvent({
    required this.title,
    required this.body,
    this.referenceType,
    this.referenceId,
    this.clubId,
    this.openedFromSystem = false,
  });

  final String title;
  final String body;
  final String? referenceType;
  final String? referenceId;
  final String? clubId;
  final bool openedFromSystem;
}

final notificationEvents = StreamController<NotificationEvent>.broadcast();

String routeForNotificationEvent(NotificationEvent event) {
  final clubId = event.clubId?.trim();
  final referenceType = event.referenceType?.trim();
  if (referenceType != null &&
      referenceType.startsWith('club_inquiry:') &&
      clubId != null &&
      clubId.isNotEmpty) {
    final threadId = referenceType.substring('club_inquiry:'.length).trim();
    if (threadId.isNotEmpty) {
      return '/clubs/$clubId/inquiries/$threadId';
    }
  }
  if (referenceType == 'club_join_request' &&
      clubId != null &&
      clubId.isNotEmpty) {
    return '/clubs/$clubId?tab=manage';
  }
  if (referenceType == 'club_approval_request') {
    final clubId = event.referenceId?.trim();
    if (clubId != null && clubId.isNotEmpty) {
      return '/admin/clubs?clubId=$clubId';
    }
    return '/admin/clubs';
  }
  if (referenceType == 'tournament_submission' ||
      referenceType == 'tournament_approval_request') {
    final tournamentId = event.referenceId?.trim();
    if (tournamentId != null && tournamentId.isNotEmpty) {
      return '/admin/edit/$tournamentId';
    }
    return '/admin/drafts';
  }
  // 랭킹 연결은 받는 사람이 갈린다 — 관리자는 승인 큐로, 신청자는 기록장으로.
  // NotificationEvent 에 type 이 없어 reference_type 두 값으로 가른다.
  if (referenceType == 'ranking_claim_request') return '/admin/ranking-claims';
  if (referenceType == 'ranking_claim_result') return '/rankings/me';
  if (referenceType == 'tournament') {
    final tournamentId = event.referenceId?.trim();
    if (tournamentId != null && tournamentId.isNotEmpty) {
      return '/tournaments/$tournamentId';
    }
  }
  if (clubId != null && clubId.isNotEmpty) return '/clubs/$clubId';
  return '/notifications';
}
