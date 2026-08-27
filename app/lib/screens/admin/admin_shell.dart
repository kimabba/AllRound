import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config.dart';
import '../../services/session_security.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';

class AdminShell extends ConsumerWidget {
  final Widget child;

  const AdminShell({
    super.key,
    required this.child,
    this.forceWebLayoutForTest = false,
  });

  @visibleForTesting
  final bool forceWebLayoutForTest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (AppConfig.adminDesignPreview || forceWebLayoutForTest) {
      return _AdminWebFrame(child: child);
    }

    final isAdminAsync = ref.watch(isAdminProvider);

    return isAdminAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('오류: $e'))),
      data: (isAdmin) {
        if (!isAdmin) return const SizedBox.shrink();
        if (!kIsWeb) return child;
        return _AdminWebFrame(child: child);
      },
    );
  }
}

class _AdminWebFrame extends StatelessWidget {
  const _AdminWebFrame({required this.child});

  static const double _sidebarBreakpoint = 840;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _sidebarBreakpoint) {
          return Scaffold(
            body: Row(
              children: [const _AdminSidebar(), Expanded(child: child)],
            ),
          );
        }

        return Scaffold(
          drawer: const Drawer(width: 220, child: _AdminSidebar()),
          body: Builder(
            builder: (scaffoldContext) => _AdminCompactScope(
              onOpenNavigation: () => Scaffold.of(scaffoldContext).openDrawer(),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

Widget? adminShellLeading(BuildContext context, {Widget? fallback}) {
  final scope =
      context.dependOnInheritedWidgetOfExactType<_AdminCompactScope>();
  if (scope == null) return fallback;
  return IconButton(
    tooltip: '관리자 메뉴',
    onPressed: scope.onOpenNavigation,
    icon: const Icon(Icons.menu_rounded),
  );
}

class _AdminCompactScope extends InheritedWidget {
  const _AdminCompactScope({
    required this.onOpenNavigation,
    required super.child,
  });

  final VoidCallback onOpenNavigation;

  @override
  bool updateShouldNotify(_AdminCompactScope oldWidget) => false;
}

class _AdminSidebar extends ConsumerWidget {
  const _AdminSidebar();

  static const _home = _AdminNavItem(
    path: '/admin',
    label: '운영 홈',
    icon: Icons.dashboard_rounded,
  );

  static const _sections = <_AdminNavSection>[
    _AdminNavSection(
      label: '대회 운영',
      items: [
        _AdminNavItem(
          path: '/admin/drafts',
          label: '제보 · Draft 검수',
          icon: Icons.fact_check_rounded,
        ),
        _AdminNavItem(
          path: '/admin/format-review',
          label: '요강 정형화 검수',
          icon: Icons.rule_folder_rounded,
        ),
        _AdminNavItem(
          path: '/admin/tournaments',
          label: '공개 대회 관리',
          icon: Icons.event_note_rounded,
        ),
        _AdminNavItem(
          path: '/admin/crawl-status',
          label: '수집 상태',
          icon: Icons.monitor_heart_rounded,
        ),
        _AdminNavItem(
          path: '/admin/sources',
          label: '수집 소스 설정',
          icon: Icons.settings_input_antenna_rounded,
        ),
      ],
    ),
    _AdminNavSection(
      label: '지식베이스',
      items: [
        _AdminNavItem(
          path: '/admin/kb',
          label: '문서 관리',
          icon: Icons.menu_book_rounded,
        ),
      ],
    ),
    _AdminNavSection(
      label: '협회 · 랭킹',
      items: [
        _AdminNavItem(
          path: '/admin/ranking-claims',
          label: '랭킹 연결 심사',
          icon: Icons.workspace_premium_rounded,
        ),
      ],
    ),
    _AdminNavSection(
      label: '클럽 · 커뮤니티',
      items: [
        _AdminNavItem(
          path: '/admin/clubs',
          label: '클럽 승인',
          icon: Icons.groups_rounded,
        ),
        _AdminNavItem(
          path: '/admin/reports',
          label: '신고 · 제재',
          icon: Icons.gavel_rounded,
        ),
      ],
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
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xxl,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '올라운드',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '운영 콘솔',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Nav items
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                children: [
                  _AdminNavTile(item: _home, currentLocation: currentLocation),
                  const SizedBox(height: AppSpacing.sm),
                  for (final section in _sections) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.md,
                        AppSpacing.md,
                        AppSpacing.xs,
                      ),
                      child: Text(
                        section.label,
                        style: textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    for (final item in section.items)
                      _AdminNavTile(
                        item: item,
                        currentLocation: currentLocation,
                      ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            // Footer: user email + logout
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (user?.email != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Text(
                        user!.email!,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.home_rounded, size: 18),
                    label: const Text('앱 화면으로'),
                    onPressed: () => context.go('/'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text('로그아웃'),
                    onPressed: () async {
                      await signOutSecurely(Supabase.instance.client);
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

class _AdminNavTile extends StatelessWidget {
  const _AdminNavTile({required this.item, required this.currentLocation});

  final _AdminNavItem item;
  final String currentLocation;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final selected = currentLocation == item.path ||
        (item.path != '/admin' && currentLocation.startsWith(item.path));

    return ListTile(
      key: ValueKey('admin-nav-${item.path}'),
      leading: Icon(
        item.icon,
        size: 20,
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
          fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      selected: selected,
      selectedTileColor: colorScheme.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      onTap: () => _navigate(context),
    );
  }

  Future<void> _navigate(BuildContext context) async {
    final router = GoRouter.of(context);
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold?.isDrawerOpen ?? false) {
      await Navigator.of(context).maybePop();
    }
    router.go(item.path);
  }
}

class _AdminNavSection {
  const _AdminNavSection({required this.label, required this.items});

  final String label;
  final List<_AdminNavItem> items;
}

class _AdminNavItem {
  const _AdminNavItem({
    required this.path,
    required this.label,
    required this.icon,
  });

  final String path;
  final String label;
  final IconData icon;
}
