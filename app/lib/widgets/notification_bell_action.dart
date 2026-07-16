import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/providers.dart';

/// 앱 상단바 오른쪽에 고정하는 알림함 진입 버튼.
///
/// 새 알림 수는 화면 진입·앱 복귀·30초 주기로 갱신해, 푸시가 늦거나
/// 비활성화된 환경에서도 빨간 배지가 오래 뒤처지지 않게 한다.
class NotificationBellAction extends ConsumerStatefulWidget {
  const NotificationBellAction({super.key});

  @override
  ConsumerState<NotificationBellAction> createState() =>
      _NotificationBellActionState();
}

class _NotificationBellActionState extends ConsumerState<NotificationBellAction>
    with WidgetsBindingObserver {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refresh(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() {
    if (mounted) ref.invalidate(unreadNotificationCountProvider);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final unread = ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0;
    final currentPath =
        GoRouter.of(context).routeInformationProvider.value.uri.path;
    final inNotificationInbox = currentPath == '/notifications';

    return IconButton(
      tooltip: unread > 0 ? '새 알림 $unread개' : '알림함',
      onPressed:
          inNotificationInbox ? _refresh : () => context.push('/notifications'),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        backgroundColor: cs.error,
        textColor: cs.onError,
        child: Icon(
          unread > 0
              ? Icons.notifications_rounded
              : Icons.notifications_none_rounded,
        ),
      ),
    );
  }
}
