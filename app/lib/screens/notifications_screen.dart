import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/app_notification.dart';
import '../state/providers.dart';
import '../theme/tokens.dart';
import '../widgets/app_card.dart';
import '../widgets/allround_logo.dart';

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
    return ref.read(apiProvider).myNotifications(limit: 100);
  }

  Future<void> _refresh() async {
    ref.invalidate(unreadNotificationCountProvider);
    final future = _load();
    setState(() => _future = future);
    await future;
  }

  Future<void> _openNotification(AppNotification notification) async {
    if (!notification.isRead) {
      await ref.read(apiProvider).markNotificationRead(notification.id);
      ref.invalidate(unreadNotificationCountProvider);
      await _refresh();
    }

    if (!mounted) return;
    final clubId = notification.clubId;
    if (clubId != null && clubId.isNotEmpty) {
      context.push('/clubs/$clubId');
    }
  }

  Future<void> _markAllRead() async {
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
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: const [
            AllRoundLogo(fontSize: 18),
            SizedBox(width: AppSpacing.sm),
            Text('알림함'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _markAllRead,
            child: const Text('전체 읽음'),
          ),
        ],
      ),
      body: FutureBuilder<List<AppNotification>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: AppCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 32),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        '알림을 불러오지 못했습니다',
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '잠시 후 다시 시도해주세요.',
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton(
                        onPressed: _refresh,
                        child: const Text('다시 시도'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          final notifications = snapshot.data ?? const [];
          if (notifications.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: AppCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.notifications_none_rounded, size: 32),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        '새 알림이 없습니다',
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '가입 신청, 승인, 공지 알림이 여기에 표시됩니다.',
                        textAlign: TextAlign.center,
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: notifications.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final item = notifications[index];
                return DecoratedBox(
                  decoration: BoxDecoration(
                    color: item.isRead
                        ? cs.surface
                        : cs.primaryContainer.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: AppCard(
                    variant: item.isRead
                        ? AppCardVariant.outlined
                        : AppCardVariant.elevated,
                    padding: EdgeInsets.zero,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      onTap: () => _openNotification(item),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: item.isRead
                                    ? cs.surfaceContainerHighest
                                    : cs.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                _iconFor(item.type),
                                size: 20,
                                color: item.isRead
                                    ? cs.onSurfaceVariant
                                    : cs.onPrimaryContainer,
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
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                      if (!item.isRead)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: cs.primary,
                                            borderRadius:
                                                BorderRadius.circular(99),
                                          ),
                                          child: Text(
                                            '새 알림',
                                            style: tt.labelSmall?.copyWith(
                                              color: cs.onPrimary,
                                              fontWeight: FontWeight.w800,
                                            ),
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
                            const SizedBox(width: AppSpacing.sm),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: cs.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

IconData _iconFor(String type) {
  switch (type) {
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
