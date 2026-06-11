import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'config.dart';
import 'screens/admin/admin_screen.dart';
import 'screens/admin/admin_shell.dart';
import 'screens/admin/no_access_screen.dart';
import 'screens/admin/tournament_edit_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/onboarding_screen.dart';
import 'screens/chat_screen.dart';
import 'models/tournament.dart';
import 'screens/clubs/club_detail_screen.dart';
import 'screens/clubs_screen.dart';
import 'screens/favorites_screen.dart';
import 'screens/more_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/rules_screen.dart';
// 웹은 dart:io 미지원 → stub 사용
import 'screens/speed_gun/speed_gun_screen.dart'
    if (dart.library.html) 'screens/speed_gun/speed_gun_screen_web.dart';
import 'screens/tournaments/tournament_detail_screen.dart';
import 'screens/tournaments/tournament_submit_screen.dart';
import 'screens/tournaments/tournaments_screen.dart';
import 'state/providers.dart';
import 'theme/tokens.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: GoRouterRefreshStream(ref),
    redirect: (context, state) async {
      final user = ref.read(currentUserProvider);
      final loc = state.matchedLocation;
      final adminDesignPreview = kIsWeb && AppConfig.adminDesignPreview;
      final userDesignPreview = kIsWeb && AppConfig.userDesignPreview;

      if (adminDesignPreview && loc.startsWith('/admin')) {
        return null;
      }

      if (userDesignPreview && !loc.startsWith('/admin')) {
        if (loc == '/login') return '/';
        return null;
      }

      if (user == null) {
        return loc == '/login' ? null : '/login';
      }

      // 웹: onboarding skip, 어드민 전용
      if (kIsWeb) {
        final adminAsync = ref.read(isAdminProvider);
        if (adminAsync.isLoading) return null; // 로딩 중 redirect 보류
        final isAdmin = adminAsync.valueOrNull ?? false;

        if (loc == '/login') return '/admin';
        if (loc.startsWith('/admin')) {
          return isAdmin ? null : '/no-access';
        }
        if (loc == '/no-access') {
          return isAdmin ? '/admin' : null;
        }
        // 웹에서 앱 경로 접근 시
        return isAdmin ? '/admin' : '/no-access';
      }

      // 앱: 기존 로직
      final sportsAsync = ref.read(userSportsProvider);
      if (sportsAsync.isLoading) return null;
      final sports = sportsAsync.valueOrNull ?? const [];
      if (sports.isEmpty && loc != '/onboarding') return '/onboarding';

      // 앱에서는 어드민 경로 완전 차단 (웹 전용)
      if (loc.startsWith('/admin')) return '/';

      if (loc == '/login') return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => _MainShell(child: child),
        routes: [
          GoRoute(path: '/', builder: (_, __) => const ChatScreen()),
          GoRoute(
            path: '/tournaments',
            builder: (_, __) => const TournamentsScreen(),
          ),
          GoRoute(path: '/clubs', builder: (_, __) => const ClubsScreen()),
          GoRoute(path: '/more', builder: (_, __) => const MoreScreen()),
          GoRoute(
            path: '/speed-gun',
            builder: (_, __) => const SpeedGunScreen(),
          ),
          GoRoute(path: '/rules', builder: (_, __) => const RulesScreen()),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
          GoRoute(
            path: '/favorites',
            builder: (_, __) => const FavoritesScreen(),
          ),
        ],
      ),
      // 웹 전용
      GoRoute(path: '/no-access', builder: (_, __) => const NoAccessScreen()),

      // Admin routes (AdminShell wrapping)
      ShellRoute(
        builder: (context, state, child) => AdminShell(child: child),
        routes: [
          GoRoute(path: '/admin', builder: (_, __) => const AdminScreen()),
          GoRoute(
            path: '/admin/drafts',
            builder: (_, __) => const AdminScreen(initialTab: 1),
          ),
          GoRoute(
            path: '/admin/sources',
            builder: (_, __) => const AdminScreen(initialTab: 2),
          ),
          GoRoute(
            path: '/admin/clubs',
            builder: (_, __) => const AdminScreen(initialTab: 3),
          ),
          GoRoute(
            path: '/admin/kb',
            builder: (_, __) => const AdminScreen(initialTab: 4),
          ),
          GoRoute(
            path: '/admin/tournaments',
            builder: (_, __) => const _AdminTournamentListScreen(),
          ),
          GoRoute(
            path: '/admin/edit/:id',
            builder: (_, state) => TournamentEditScreen(
              tournamentId: state.pathParameters['id']!,
            ),
          ),
        ],
      ),

      GoRoute(
        path: '/tournaments/submit',
        builder: (_, __) => const TournamentSubmitScreen(),
      ),
      GoRoute(
        path: '/clubs/:id',
        builder: (_, state) => ClubDetailScreen(club: state.extra as Club),
      ),
      GoRoute(
        path: '/tournaments/:id',
        builder: (_, state) =>
            TournamentDetailScreen(tournamentId: state.pathParameters['id']!),
      ),
    ],
  );
});

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Ref ref) {
    ref.listen(authStateProvider, (_, __) => notifyListeners());
    ref.listen(userSportsProvider, (_, __) => notifyListeners());
    ref.listen(isAdminProvider, (_, __) => notifyListeners());
  }
}

class _MainShell extends ConsumerWidget {
  const _MainShell({required this.child});
  final Widget child;

  static const _tabs = [
    ('/', Icons.auto_awesome_outlined, '코치봇'),
    ('/tournaments', Icons.emoji_events_outlined, '대회'),
    ('/clubs', Icons.groups_outlined, '클럽'),
    ('/more', Icons.grid_view_outlined, '더보기'),
  ];

  // 더보기 하위 경로는 더보기 탭이 선택된 것으로 표시
  static const _moreSubPaths = [
    '/more',
    '/speed-gun',
    '/rules',
    '/profile',
    '/favorites',
  ];

  int _indexOf(String location) {
    for (var i = 0; i < _tabs.length; i++) {
      if (_tabs[i].$1 == '/more') {
        if (_moreSubPaths.any(
          (p) => location == p || (location.startsWith(p) && p != '/'),
        )) {
          return i;
        }
      } else if (location == _tabs[i].$1 ||
          (location.startsWith(_tabs[i].$1) && _tabs[i].$1 != '/')) {
        return i;
      }
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = GoRouterState.of(context).matchedLocation;
    final idx = _indexOf(loc);
    final cs = Theme.of(context).colorScheme;
    final activeSport = ref.watch(activeSportProvider);

    return Scaffold(
      body: Column(
        children: [
          // 종목 스왑 바
          SafeArea(
            bottom: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          activeSport == 'futsal'
                              ? Icons.sports_soccer_rounded
                              : Icons.sports_tennis_rounded,
                          size: 18,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'tennis',
                              label: Text('테니스'),
                              icon: Icon(Icons.sports_tennis_rounded),
                            ),
                            ButtonSegment(
                              value: 'futsal',
                              label: Text('풋살'),
                              icon: Icon(Icons.sports_soccer_rounded),
                            ),
                          ],
                          selected: {activeSport ?? 'tennis'},
                          onSelectionChanged: (s) {
                            ref.read(sportOverrideProvider.notifier).state =
                                s.first;
                          },
                          style: SegmentedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: cs.surfaceContainerLowest,
              child: child,
            ),
          ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
          boxShadow: AppShadows.cardFor(Theme.of(context).brightness),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: NavigationBar(
              selectedIndex: idx,
              onDestinationSelected: (i) => context.go(_tabs[i].$1),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              height: 66,
              destinations: [
                for (final t in _tabs)
                  NavigationDestination(
                    icon: Icon(t.$2),
                    selectedIcon: Icon(_selectedIcon(t.$2)),
                    label: t.$3,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _selectedIcon(IconData icon) {
    return switch (icon) {
      Icons.auto_awesome_outlined => Icons.auto_awesome_rounded,
      Icons.emoji_events_outlined => Icons.emoji_events_rounded,
      Icons.groups_outlined => Icons.groups_rounded,
      Icons.grid_view_outlined => Icons.grid_view_rounded,
      _ => icon,
    };
  }
}

class _AdminTournamentListScreen extends ConsumerWidget {
  const _AdminTournamentListScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supabase = ref.read(supabaseProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('대회 편집')),
      body: FutureBuilder(
        future: supabase
            .from('tournaments')
            .select('id, title, sport, region, start_date, status')
            .order('start_date', ascending: false)
            .limit(100),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data as List;
          if (rows.isEmpty) {
            return const Center(child: Text('대회 없음'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (_, i) {
              final r = rows[i];
              final statusColor = r['status'] == 'published'
                  ? Colors.green
                  : (r['status'] == 'draft' ? Colors.orange : Colors.grey);
              return ListTile(
                title: Text(r['title'] ?? ''),
                subtitle: Text(
                  '${r['sport']} · ${r['region'] ?? ''} · ${r['start_date']}',
                ),
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    r['status'] ?? '',
                    style: TextStyle(color: statusColor, fontSize: 12),
                  ),
                ),
                onTap: () => context.go('/admin/edit/${r['id']}'),
              );
            },
          );
        },
      ),
    );
  }
}
