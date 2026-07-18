import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config.dart';
import '../models/moderation.dart';
import '../state/providers.dart';
import '../theme/tokens.dart';
import '../widgets/app_empty_state.dart';

class BlockedUsersScreen extends ConsumerStatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  ConsumerState<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends ConsumerState<BlockedUsersScreen> {
  late Future<List<BlockedUser>> _future;
  final Set<String> _busyUserIds = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = AppConfig.userDesignPreview
        ? Future.value(_previewBlockedUsers)
        : ref.read(apiProvider).myBlockedUsers();
  }

  Future<void> _unblock(BlockedUser user) async {
    if (AppConfig.userDesignPreview) {
      setState(() {
        _future = Future.value(
          _previewBlockedUsers
              .where((item) => item.userId != user.userId)
              .toList(growable: false),
        );
      });
      return;
    }
    setState(() => _busyUserIds.add(user.userId));
    try {
      await ref.read(apiProvider).unblockUser(user.userId);
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${user.displayName} 님의 차단을 해제했습니다.')),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('차단을 해제하지 못했습니다.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyUserIds.remove(user.userId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('차단 관리')),
      body: FutureBuilder<List<BlockedUser>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return AppEmptyState(
              icon: Icons.person_off_outlined,
              title: '차단 목록을 불러오지 못했습니다',
              description: '연결 상태를 확인한 뒤 다시 시도해 주세요.',
              actionLabel: '다시 불러오기',
              onAction: () => setState(_reload),
            );
          }
          final users = snapshot.data ?? const [];
          if (users.isEmpty) {
            return const AppEmptyState(
              icon: Icons.person_off_outlined,
              title: '차단한 사용자가 없습니다',
              description: '차단한 사용자는 내 클럽 활동과 게시글에서 숨겨집니다.',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.sm,
              AppSpacing.xl,
              AppSpacing.xxxl,
            ),
            children: [
              Text(
                '차단한 사용자는 내 콘텐츠에 댓글을 남기거나 클럽 활동을 볼 수 없습니다.',
                style: tt.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              for (var index = 0; index < users.length; index++) ...[
                _BlockedUserRow(
                  user: users[index],
                  busy: _busyUserIds.contains(users[index].userId),
                  onUnblock: () => _unblock(users[index]),
                ),
                if (index != users.length - 1)
                  Divider(height: 1, color: cs.outlineVariant),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _BlockedUserRow extends StatelessWidget {
  const _BlockedUserRow({
    required this.user,
    required this.busy,
    required this.onUnblock,
  });

  final BlockedUser user;
  final bool busy;
  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child:
                Icon(Icons.person_outline_rounded, color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.displayName, style: tt.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '차단일 ${_date(user.blockedAt)}',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: busy ? null : onUnblock,
            child: Text(busy ? '처리 중…' : '해제'),
          ),
        ],
      ),
    );
  }
}

String _date(DateTime value) {
  final local = value.toLocal();
  return '${local.year}.${local.month}.${local.day}';
}

final _previewBlockedUsers = [
  BlockedUser(
    userId: 'preview-user-1',
    displayName: '테니스광고계정',
    blockedAt: DateTime(2026, 7, 12),
  ),
  BlockedUser(
    userId: 'preview-user-2',
    displayName: '매너없는플레이어',
    blockedAt: DateTime(2026, 6, 28),
  ),
];
