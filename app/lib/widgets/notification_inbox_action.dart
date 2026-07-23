import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/providers.dart';

/// 모든 주요 탭의 같은 위치에서 알림함으로 이동하는 공통 액션.
class NotificationInboxAction extends ConsumerWidget {
  const NotificationInboxAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0;
    return Badge(
      isLabelVisible: unread > 0,
      label: Text(unread > 99 ? '99+' : '$unread'),
      child: IconButton(
        tooltip: unread > 0 ? '읽지 않은 알림 $unread개' : '알림함',
        onPressed: () => context.push('/notifications'),
        icon: const Icon(Icons.notifications_none_rounded),
      ),
    );
  }
}
