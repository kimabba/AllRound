import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'screens/admin/admin_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/onboarding_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/clubs_screen.dart';
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

      if (user == null) {
        return loc == '/login' ? null : '/login';
      }

      // 종목·등급 미등록 사용자는 온보딩으로 강제
      // userSportsProvider 가 로딩 중이면 redirect 보류 (깜빡임 방지)
      final sportsAsync = ref.read(userSportsProvider);
      if (sportsAsync.isLoading) return null;
      final sports = sportsAsync.valueOrNull ?? const [];
      if (sports.isEmpty && loc != '/onboarding') return '/onboarding';

      // /admin 비어드민 접근 차단
      if (loc == '/admin') {
        final isAdmin = ref.read(isAdminProvider).valueOrNull ?? false;
        if (!isAdmin) return '/';
      }

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
          GoRoute(path: '/admin', builder: (_, __) => const AdminScreen()),
        ],
      ),
      GoRoute(
        path: '/tournaments/submit',
        builder: (_, __) => const TournamentSubmitScreen(),
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
    '/admin',
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              child: Row(
                children: [
                  Icon(
                    activeSport == 'futsal'
                        ? Icons.sports_soccer_rounded
                        : Icons.sports_tennis_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'tennis', label: Text('테니스')),
                      ButtonSegment(value: 'futsal', label: Text('풋살')),
                    ],
                    selected: {activeSport ?? 'tennis'},
                    onSelectionChanged: (s) {
                      ref.read(sportOverrideProvider.notifier).state = s.first;
                    },
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
          boxShadow: AppShadows.cardFor(Theme.of(context).brightness),
        ),
        child: NavigationBar(
          selectedIndex: idx,
          onDestinationSelected: (i) => context.go(_tabs[i].$1),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
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
