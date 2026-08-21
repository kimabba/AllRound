import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/providers.dart';
import '../testing/e2e_keys.dart';

/// 모든 주요 탭의 같은 위치에서 마이(프로필·설정)로 이동하는 공통 설정 액션.
/// 마이가 하단 메뉴에서 빠지면서 이 아이콘이 주요 진입점이 된다 —
/// 주요 화면 앱바에 놓아 어디서든 같은 자리에서 들어갈 수 있게 한다.
class ProfileAction extends StatelessWidget {
  const ProfileAction({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: AllRoundE2EKeys.navProfile,
      tooltip: '마이 및 설정',
      onPressed: () => context.push('/profile'),
      icon: const Icon(Icons.settings_outlined),
    );
  }
}

/// 모든 주요 탭의 같은 위치에서 알림함으로 이동하는 공통 액션.
class NotificationInboxAction extends ConsumerWidget {
  const NotificationInboxAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationCountProvider).value ?? 0;
    return IconButton(
      tooltip: unread > 0 ? '읽지 않은 알림 $unread개' : '알림함',
      onPressed: () => context.push('/notifications'),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        // IconButton 전체(48x48 터치 영역)가 아니라 아이콘 자체에 배지를 붙여야
        // 종처럼 붙어 보인다 — IconButton 을 통째로 감싸면 배지가 모서리로 밀린다.
        child: const Icon(Icons.notifications_none_rounded),
      ),
    );
  }
}
