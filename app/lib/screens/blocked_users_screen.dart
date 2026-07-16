import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/moderation.dart';
import '../state/providers.dart';
import '../theme/tokens.dart';
import '../widgets/allround_logo.dart';
import '../widgets/notification_bell_action.dart';

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
    _future = ref.read(apiProvider).myBlockedUsers();
  }

  Future<void> _unblock(BlockedUser user) async {
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
    return Scaffold(
      appBar: AppBar(
        title: const BrandedAppBarTitle(title: '차단 관리'),
        actions: const [NotificationBellAction()],
      ),
      body: FutureBuilder<List<BlockedUser>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: FilledButton.tonalIcon(
                onPressed: () => setState(_reload),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('다시 시도'),
              ),
            );
          }
          final users = snapshot.data ?? const [];
          if (users.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_off_outlined,
                        size: 48, color: cs.onSurfaceVariant),
                    const SizedBox(height: AppSpacing.md),
                    const Text('차단한 사용자가 없습니다.'),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: users.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, index) {
              final user = users[index];
              final busy = _busyUserIds.contains(user.userId);
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
                title: Text(user.displayName),
                subtitle: Text('차단일 ${_date(user.blockedAt)}'),
                trailing: OutlinedButton(
                  onPressed: busy ? null : () => _unblock(user),
                  child: Text(busy ? '처리 중…' : '차단 해제'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

String _date(DateTime value) {
  final local = value.toLocal();
  return '${local.year}.${local.month}.${local.day}';
}
