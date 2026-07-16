import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config.dart';
import '../models/app_notification.dart';
import '../state/providers.dart';
import '../testing/e2e_keys.dart';
import '../theme/tokens.dart';
import '../widgets/app_empty_state.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  late Future<List<AppNotification>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<AppNotification>> _load() {
    if (AppConfig.userDesignPreview) {
      return Future.value(_previewNotifications);
    }
    return ref.read(apiProvider).myNotifications(limit: 100);
  }

  Future<void> _refresh() async {
    ref.invalidate(unreadNotificationCountProvider);
    final future = _load();
    setState(() => _future = future);
    await future;
  }

  Future<void> _openNotification(AppNotification notification) async {
    if (!notification.isRead && !AppConfig.userDesignPreview) {
      await ref.read(apiProvider).markNotificationRead(notification.id);
      ref.invalidate(unreadNotificationCountProvider);
      await _refresh();
    }

    if (!mounted) return;
    final referenceId = notification.referenceId;
    if (notification.referenceType == 'club_approval_request') {
      context.push('/admin/clubs');
      return;
    }
    if (notification.referenceType == 'tournament' &&
        referenceId != null &&
        referenceId.isNotEmpty) {
      context.push('/tournaments/$referenceId');
      return;
    }
    final clubId = notification.clubId;
    if (clubId != null && clubId.isNotEmpty) {
      context.push('/clubs/$clubId');
    }
  }

  Future<void> _markAllRead() async {
    if (AppConfig.userDesignPreview) return;
    await ref.read(apiProvider).markAllNotificationsRead();
    ref.invalidate(unreadNotificationCountProvider);
    await _refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('모든 알림을 읽음으로 표시했습니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      key: AllRoundE2EKeys.notificationsScreen,
      appBar: AppBar(
        title: const Text('알림'),
        actions: [
          TextButton(
            onPressed: AppConfig.userDesignPreview ? null : _markAllRead,
            child: const Text('전체 읽음'),
          ),
        ],
      ),
      body: FutureBuilder<List<AppNotification>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _NotificationLoadingState();
          }
          if (snapshot.hasError) {
            return AppEmptyState(
              icon: Icons.notifications_off_outlined,
              title: '알림을 불러오지 못했습니다',
              description: '연결 상태를 확인한 뒤 다시 시도해 주세요.',
              actionLabel: '다시 불러오기',
              onAction: _refresh,
            );
          }

          final notifications = snapshot.data ?? const [];
          if (notifications.isEmpty) {
            return const KeyedSubtree(
              key: AllRoundE2EKeys.notificationsReady,
              child: AppEmptyState(
                icon: Icons.notifications_none_rounded,
                title: '새 알림이 없습니다',
                description: '대회 마감, 가입 신청과 클럽 공지를 여기에서 확인할 수 있어요.',
              ),
            );
          }

          return KeyedSubtree(
            key: AllRoundE2EKeys.notificationsReady,
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.sm,
                  AppSpacing.xl,
                  AppSpacing.xxxl,
                ),
                itemCount: notifications.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: cs.outlineVariant,
                ),
                itemBuilder: (context, index) {
                  final item = notifications[index];
                  return Material(
                    color: item.isRead ? cs.surface : cs.primaryContainer,
                    child: InkWell(
                      onTap: () => _openNotification(item),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.lg,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: item.isRead
                                    ? cs.surfaceContainerHighest
                                    : cs.primary,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.md,
                                ),
                              ),
                              child: Icon(
                                _iconFor(item.type),
                                size: 20,
                                color: item.isRead
                                    ? cs.onSurfaceVariant
                                    : cs.onPrimary,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.title,
                                          style: tt.titleSmall?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      if (!item.isRead)
                                        Container(
                                          width: 7,
                                          height: 7,
                                          decoration: BoxDecoration(
                                            color: cs.primary,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    item.typeLabel,
                                    style: tt.labelMedium?.copyWith(
                                      color: cs.primary,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  if (item.body != null &&
                                      item.body!.trim().isNotEmpty) ...[
                                    const SizedBox(height: AppSpacing.xs),
                                    Text(
                                      item.body!,
                                      style: tt.bodyMedium?.copyWith(
                                        color: cs.onSurfaceVariant,
                                        height: 1.45,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: AppSpacing.sm),
                                  Text(
                                    _formatNotificationDate(item.createdAt),
                                    style: tt.labelSmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NotificationLoadingState extends StatelessWidget {
  const _NotificationLoadingState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.xxxl,
      ),
      itemCount: 4,
      separatorBuilder: (_, __) => Divider(color: cs.outlineVariant),
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 14, color: cs.surfaceContainerHighest),
                  const SizedBox(height: AppSpacing.sm),
                  FractionallySizedBox(
                    widthFactor: 0.62,
                    child: Container(
                      height: 10,
                      color: cs.surfaceContainerHighest,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _iconFor(String type) {
  switch (type) {
    case 'club_approval_request':
      return Icons.admin_panel_settings_rounded;
    case 'club_join_request':
      return Icons.person_add_alt_1_rounded;
    case 'club_join_approved':
      return Icons.verified_rounded;
    case 'club_join_rejected':
      return Icons.block_rounded;
    case 'club_notice':
      return Icons.push_pin_outlined;
    case 'club_event':
      return Icons.event_outlined;
    case 'tournament_d3':
      return Icons.event_available_rounded;
    case 'tournament_deadline':
      return Icons.timer_rounded;
    default:
      return Icons.notifications_outlined;
  }
}

String _formatNotificationDate(DateTime date) {
  final local = date.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.month}/${local.day} $hour:$minute';
}

final _previewNotifications = [
  AppNotification(
    id: 'preview-notification-1',
    type: 'tournament_deadline',
    title: '서울 오픈 신청이 오늘 마감됩니다',
    body: '신청을 마치려면 대회 상세에서 접수처를 확인하세요.',
    referenceType: 'tournament',
    referenceId: 'preview-tennis-seoul-open',
    isRead: false,
    createdAt: DateTime(2026, 7, 18, 9, 30),
  ),
  AppNotification(
    id: 'preview-notification-2',
    type: 'club_event',
    title: '서울 풋살 러너스 일정이 등록됐습니다',
    body: '7월 20일 오후 7시 잠실 풋살장',
    clubId: 'preview-club-futsal',
    isRead: false,
    createdAt: DateTime(2026, 7, 17, 19, 10),
  ),
  AppNotification(
    id: 'preview-notification-3',
    type: 'club_join_approved',
    title: '클럽 가입이 승인되었습니다',
    body: '광주 테니스 크루의 일정과 게시판을 이용할 수 있어요.',
    clubId: 'preview-club-tennis',
    isRead: true,
    createdAt: DateTime(2026, 7, 16, 14, 5),
  ),
];
