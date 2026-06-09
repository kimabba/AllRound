import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config.dart';
import '../../state/providers.dart';

class AdminShell extends ConsumerWidget {
  final Widget child;

  const AdminShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (AppConfig.adminDesignPreview) {
      return Scaffold(
        body: Row(
          children: [
            const _AdminSidebar(),
            Expanded(child: child),
          ],
        ),
      );
    }

    final isAdminAsync = ref.watch(isAdminProvider);

    return isAdminAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(child: Text('오류: $e')),
      ),
      data: (isAdmin) {
        if (!isAdmin) return const SizedBox.shrink();
        return Scaffold(
          body: Row(
            children: [
              const _AdminSidebar(),
              Expanded(child: child),
            ],
          ),
        );
      },
    );
  }
}

class _AdminSidebar extends ConsumerWidget {
  const _AdminSidebar();

  static const _items = [
    (path: '/admin', label: '대시보드', icon: Icons.dashboard_outlined),
    (path: '/admin/drafts', label: 'Draft 승인', icon: Icons.fact_check_outlined),
    (path: '/admin/sources', label: '크롤 소스', icon: Icons.rss_feed_outlined),
    (path: '/admin/clubs', label: '클럽 승인', icon: Icons.groups_outlined),
    (path: '/admin/kb', label: '지식베이스', icon: Icons.menu_book_outlined),
    (
      path: '/admin/tournaments',
      label: '대회 편집',
      icon: Icons.edit_note_outlined
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLocation = GoRouterState.of(context).matchedLocation;
    final user = ref.watch(currentUserProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SizedBox(
      width: 220,
      child: Material(
        color: colorScheme.surface,
        elevation: 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              child: Text(
                'Match-up',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
            ),
            const Divider(height: 1),
            // Nav items
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: _items.map((item) {
                  final selected = currentLocation == item.path ||
                      (item.path != '/admin' &&
                          currentLocation.startsWith(item.path));
                  return ListTile(
                    leading: Icon(
                      item.icon,
                      color: selected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
                    ),
                    title: Text(
                      item.label,
                      style: textTheme.bodyMedium?.copyWith(
                        color: selected
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurfaceVariant,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    selected: selected,
                    selectedTileColor: colorScheme.primaryContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    onTap: () => context.go(item.path),
                  );
                }).toList(),
              ),
            ),
            const Divider(height: 1),
            // Footer: user email + logout
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (user?.email != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        user!.email!,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.logout, size: 16),
                    label: const Text('로그아웃'),
                    onPressed: () async {
                      await Supabase.instance.client.auth.signOut();
                    },
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
