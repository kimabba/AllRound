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
  if (referenceType == 'club_approval_request') return '/admin/clubs';
  if (referenceType == 'tournament') {
    final tournamentId = event.referenceId?.trim();
    if (tournamentId != null && tournamentId.isNotEmpty) {
      return '/tournaments/$tournamentId';
    }
  }
  if (clubId != null && clubId.isNotEmpty) return '/clubs/$clubId';
  return '/notifications';
}
