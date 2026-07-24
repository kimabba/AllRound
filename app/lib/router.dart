import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'config.dart';
import 'screens/admin/admin_screen.dart';
import 'screens/admin/admin_shell.dart';
import 'screens/admin/no_access_screen.dart';
import 'screens/admin/format_review_screen.dart';
import 'screens/admin/moderation_screen.dart';
import 'screens/admin/tournament_edit_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/onboarding_screen.dart';
import 'screens/auth/verify_phone_screen.dart';
import 'screens/auth/reset_password_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/blocked_users_screen.dart';
import 'models/chat_entry_context.dart';
import 'models/tournament.dart';
import 'screens/clubs/club_detail_screen.dart';
import 'screens/clubs/club_inquiry_screen.dart';
import 'screens/clubs_screen.dart';
import 'screens/favorites_screen.dart';
import 'screens/home_screen.dart';
import 'screens/more_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/rules_screen.dart';
import 'screens/tournaments/tournament_detail_screen.dart';
import 'screens/tournaments/tournament_submit_screen.dart';
import 'screens/tournaments/tournaments_screen.dart';
import 'state/providers.dart';
import 'widgets/app_bottom_nav.dart';
import 'widgets/chat_sheet.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: kIsWeb && AppConfig.userDesignPreview
        ? (Uri.base.path.isEmpty ? '/' : Uri.base.path)
        : '/',
    refreshListenable: GoRouterRefreshStream(ref),
    redirect: (context, state) async {
      final user = ref.read(currentUserProvider);
      final loc = state.matchedLocation;

      // 비밀번호 재설정 딥링크(passwordRecovery): 세션이 생겨 user!=null 이 되지만
      // 홈이 아니라 새 비번 설정 화면으로 보낸다. recoveryModeProvider 가 sticky
      // 하게 유지되므로 tokenRefreshed 등 다른 이벤트에 튕기지 않고, 저장 성공 시
      // 화면이 complete() 로 끄고 context.go('/') 로 빠져나간다(이벤트 타이밍 race 없음).
      if (user != null && ref.read(recoveryModeProvider)) {
        return loc == '/reset-password' ? null : '/reset-password';
      }
      final adminDesignPreview = kIsWeb && AppConfig.adminDesignPreview;
      final userDesignPreview = kIsWeb && AppConfig.userDesignPreview;

      if (adminDesignPreview && loc.startsWith('/admin')) {
        return null;
      }

      if (userDesignPreview && !loc.startsWith('/admin')) {
        return null;
      }

      if (user == null) {
        return loc == '/login' ? null : '/login';
      }

      // 웹: onboarding skip, admin 경로는 admin만 접근 가능
      if (kIsWeb) {
        final adminAsync = ref.read(isAdminProvider);
        if (adminAsync.isLoading) return null;
        final isAdmin = adminAsync.value ?? false;

        if (loc == '/login') return '/';
        if (loc.startsWith('/admin')) {
          return isAdmin ? null : '/';
        }
        return null;
      }

      // 앱: 클럽 승인은 관리자가 알림에서 바로 처리할 수 있게
      // 모바일에서도 해당 경로만 허용한다. 권한 판정은 서버 role이 기준이다.
      if (loc == '/admin/clubs') {
        final adminAsync = ref.read(isAdminProvider);
        if (adminAsync.isLoading) return null;
        return (adminAsync.value ?? false) ? null : '/';
      }

      // 앱: 온보딩 → 전화번호 인증 순차 게이트.
      // 종목 미등록이면 온보딩(연령·종목 설정)부터, 완료 후 전화번호 미인증이면
      // 인증 화면으로. 이 순서라야 verify-otp(requireVerifiedUser=연령 선행)가 성립한다.
      final sportsAsync = ref.read(userSportsProvider);
      if (sportsAsync.isLoading) return null;
      final sports = sportsAsync.value ?? const [];
      final profileAsync = ref.read(myProfileProvider);
      if (profileAsync.isLoading) return null;
      final profile = profileAsync.value;

      // 생년월일이 없으면 온보딩으로 되돌린다. 전화인증 화면으로 보내면
      // send-otp 의 연령 게이트에 막혀 빠져나올 수 없는 교착이 된다.
      final onboardingIncomplete = sports.isEmpty || profile?.birthDate == null;
      if (onboardingIncomplete) {
        if (loc != '/onboarding') return '/onboarding';
      } else if (profile?.phoneVerifiedAt == null) {
        if (loc != '/verify-phone') return '/verify-phone';
      }

      // 나머지 어드민 경로는 기존처럼 웹에서만 허용한다.
      if (loc.startsWith('/admin')) return '/';

      if (loc == '/login') return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(
        path: '/reset-password',
        builder: (_, __) => const ResetPasswordScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/verify-phone',
        builder: (_, __) => const VerifyPhoneScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => _MainShell(child: child),
        routes: [
          GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
          GoRoute(
            path: '/chat',
            builder: (_, state) {
              final extra = state.extra;
              return ChatScreen(
                entryContext: extra is ChatEntryContext ? extra : null,
              );
            },
          ),
          GoRoute(
            path: '/tournaments',
            builder: (_, __) => const TournamentsScreen(),
          ),
          GoRoute(path: '/clubs', builder: (_, __) => const ClubsScreen()),
          GoRoute(path: '/more', builder: (_, __) => const MoreScreen()),
          GoRoute(path: '/rules', builder: (_, __) => const RulesScreen()),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
          GoRoute(
            path: '/notifications',
            builder: (_, __) => const NotificationsScreen(),
          ),
          GoRoute(
            path: '/favorites',
            builder: (_, __) => const FavoritesScreen(),
          ),
          GoRoute(
            path: '/blocked-users',
            builder: (_, __) => const BlockedUsersScreen(),
          ),
          GoRoute(
            path: '/tournaments/submit',
            builder: (_, __) => const TournamentSubmitScreen(),
          ),
          GoRoute(
            path: '/clubs/:id',
            builder: (_, state) {
              final club = state.extra as Club?;
              final openManagement =
                  state.uri.queryParameters['tab'] == 'manage';
              return club != null
                  ? ClubDetailScreen(
                      club: club,
                      openManagement: openManagement,
                    )
                  : ClubDetailScreen(
                      clubId: state.pathParameters['id']!,
                      openManagement: openManagement,
                    );
            },
          ),
          GoRoute(
            path: '/tournaments/:id',
            builder: (_, state) => TournamentDetailScreen(
              tournamentId: state.pathParameters['id']!,
            ),
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
            path: '/admin/format-review',
            builder: (_, __) => const FormatReviewScreen(),
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
            path: '/admin/reports',
            builder: (_, __) => const ModerationScreen(),
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
        path: '/clubs/:id/inquiries/manage',
        builder: (_, state) => ClubInquiryInboxScreen(
          clubId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/clubs/:id/inquiries/:threadId',
        builder: (_, state) => ClubInquiryConversationScreen(
          clubId: state.pathParameters['id']!,
          threadId: state.pathParameters['threadId']!,
        ),
      ),
      GoRoute(
        path: '/clubs/:id/inquiries',
        builder: (_, state) => ClubInquiryConversationScreen(
          clubId: state.pathParameters['id']!,
        ),
      ),
    ],
  );
});

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Ref ref) {
    ref.listen(authStateProvider, (_, __) => notifyListeners());
    ref.listen(userSportsProvider, (_, __) => notifyListeners());
    ref.listen(isAdminProvider, (_, __) => notifyListeners());
    ref.listen(recoveryModeProvider, (_, __) => notifyListeners());
  }
}

class _MainShell extends ConsumerWidget {
  const _MainShell({required this.child});

  final Widget child;

  static const _tabs = <String>[
    '/',
    '/tournaments',
    '/clubs',
    '/profile',
  ];

  static const _profileSubPaths = [
    '/more',
    '/profile',
    '/notifications',
    '/favorites',
    '/blocked-users',
    '/rules',
  ];

  int _indexOf(String location) {
    for (var i = 0; i < _tabs.length; i++) {
      if (_tabs[i] == '/profile') {
        if (_profileSubPaths.any(
          (p) => location == p || (location.startsWith(p) && p != '/'),
        )) {
          return i;
        }
      } else if (location == _tabs[i] ||
          (location.startsWith(_tabs[i]) && _tabs[i] != '/')) {
        return i;
      }
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPath =
        GoRouter.of(context).routeInformationProvider.value.uri.path;
    final idx = _indexOf(currentPath);
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final isFullChat = currentPath == '/chat';
    final showChatDock = !isFullChat;

    final entryContext = chatEntryContextForPath(currentPath);

    return Scaffold(
      body: child,
      bottomNavigationBar: keyboardVisible || isFullChat
          ? null
          : AppBottomNav(
              currentIndex: idx,
              onChanged: (index) => context.go(_tabs[index]),
              onChatTap: showChatDock
                  ? () => openChatSheet(context, entryContext)
                  : null,
              chatHint: '${entryContext.screenLabel} 화면에서 채팅 열기',
            ),
    );
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
