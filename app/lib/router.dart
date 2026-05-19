import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'screens/auth/login_screen.dart';
import 'screens/auth/onboarding_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/clubs_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/rules_screen.dart';
// 웹은 dart:io 미지원 → stub 사용
import 'screens/speed_gun/speed_gun_screen.dart'
    if (dart.library.html) 'screens/speed_gun/speed_gun_screen_web.dart';
import 'screens/tournaments/tournament_detail_screen.dart';
import 'screens/tournaments/tournament_submit_screen.dart';
import 'screens/tournaments/tournaments_screen.dart';
import 'state/providers.dart';

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

      if (loc == '/login') return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      ShellRoute(
        builder: (context, state, child) => _MainShell(child: child),
        routes: [
          GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
          GoRoute(path: '/tournaments', builder: (_, __) => const TournamentsScreen()),
          GoRoute(path: '/clubs', builder: (_, __) => const ClubsScreen()),
          GoRoute(path: '/speed-gun', builder: (_, __) => const SpeedGunScreen()),
          GoRoute(path: '/rules', builder: (_, __) => const RulesScreen()),
          GoRoute(path: '/chat', builder: (_, __) => const ChatScreen()),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
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
  }
}

class _MainShell extends StatelessWidget {
  const _MainShell({required this.child});
  final Widget child;

  static List<(String, IconData, String)> get _tabs => [
    ('/', Icons.home_outlined, '홈'),
    ('/tournaments', Icons.emoji_events_outlined, '대회'),
    ('/clubs', Icons.groups_outlined, '클럽'),
    if (!kIsWeb) ('/speed-gun', Icons.speed_rounded, '스피드건'),
    ('/rules', Icons.menu_book_outlined, '룰북'),
    ('/chat', Icons.chat_bubble_outline, '챗봇'),
    ('/profile', Icons.person_outline, '내정보'),
  ];

  int _indexOf(String location) {
    for (var i = 0; i < _tabs.length; i++) {
      if (location == _tabs[i].$1 ||
          (location.startsWith(_tabs[i].$1) && _tabs[i].$1 != '/')) {
        return i;
      }
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    final idx = _indexOf(loc);
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) => context.go(_tabs[i].$1),
        destinations: [
          for (final t in _tabs)
            NavigationDestination(icon: Icon(t.$2), label: t.$3),
        ],
      ),
    );
  }
}
