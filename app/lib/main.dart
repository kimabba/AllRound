import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'router.dart';
import 'services/api.dart';
import 'services/local_user_preferences.dart';
import 'services/notifications.dart'
    if (dart.library.html) 'services/notifications_web.dart';
import 'services/notification_events.dart';
import 'state/chat_state.dart';
import 'state/providers.dart';
import 'state/theme_provider.dart';
import 'theme/app_theme.dart';
import 'utils/grade_labels.dart';
import 'widgets/allround_logo.dart';

bool _allRoundServicesInitialized = false;

/// 실제 앱과 integration_test가 같은 초기화 경로를 사용한다.
/// 테스트는 자신의 binding을 먼저 만들기 때문에 여기서 binding을 생성하지 않는다.
Future<void> initializeAllRoundServices({
  FlutterAuthClientOptions authOptions = const FlutterAuthClientOptions(),
}) async {
  if (_allRoundServicesInitialized) return;
  AppConfig.assertConfigured();

  await initializeDateFormatting('ko');

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
    authOptions: authOptions,
  );

  // 인증 후 FCM 등록 + 부서 카탈로그 DB 로드 (실패해도 앱 진입 허용)
  Supabase.instance.client.auth.onAuthStateChange.listen((event) {
    // signedIn(신규 로그인)만 보면 저장된 세션으로 앱을 재시작한 경우
    // (initialSession) FCM 리스너가 등록되지 않아 포그라운드 알림이 죽는다.
    // 중복 호출은 notifications.dart 의 _messageListenersInitialized 가 막는다.
    if (event.session != null &&
        (event.event == AuthChangeEvent.signedIn ||
            event.event == AuthChangeEvent.initialSession)) {
      initNotifications(ApiService(Supabase.instance.client));
    }
    // signedIn(신규 로그인) + initialSession(복원 세션) 모두에서 로드.
    // RLS(tennis_divisions_read = authenticated) 이므로 세션 존재 시에만.
    if (event.session != null) {
      DivisionCatalog.instance.load(Supabase.instance.client);
    }
  });

  _allRoundServicesInitialized = true;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeAllRoundServices();

  runApp(const ProviderScope(child: MatchUpApp()));
}

class MatchUpApp extends ConsumerWidget {
  const MatchUpApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!AppConfig.userDesignPreview) {
      ref.listen(authStateProvider, (previous, next) {
        final previousUserId = previous?.valueOrNull?.session?.user.id;
        final nextUserId = next.valueOrNull?.session?.user.id;
        if (previousUserId == nextUserId) return;

        ref.read(chatProvider).reset();
        if (previousUserId != null) {
          unawaited(clearLocalUserPreferences(previousUserId));
        }
      });
    }

    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: '올라운드',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ko', 'KR'),
        Locale('en', 'US'),
      ],
      locale: const Locale('ko', 'KR'),
      builder: (context, child) {
        final app = _NotificationEventListener(
          router: router,
          child: _AllRoundStartupSplash(
            child: child ?? const SizedBox.shrink(),
          ),
        );
        if (!kIsWeb || !AppConfig.userDesignPreview) return app;

        return LayoutBuilder(
          builder: (context, constraints) {
            final previewWidth =
                constraints.maxWidth < 390 ? constraints.maxWidth : 390.0;
            final previewSize = Size(previewWidth, constraints.maxHeight);
            return ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: previewWidth,
                  height: constraints.maxHeight,
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(size: previewSize),
                    child: app,
                  ),
                ),
              ),
            );
          },
        );
      },
      routerConfig: router,
    );
  }
}

class _NotificationEventListener extends ConsumerStatefulWidget {
  const _NotificationEventListener({
    required this.router,
    required this.child,
  });

  final GoRouter router;
  final Widget child;

  @override
  ConsumerState<_NotificationEventListener> createState() =>
      _NotificationEventListenerState();
}

class _NotificationEventListenerState
    extends ConsumerState<_NotificationEventListener> {
  StreamSubscription<NotificationEvent>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = notificationEvents.stream.listen(_handleNotification);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _handleNotification(NotificationEvent event) {
    ref.invalidate(unreadNotificationCountProvider);
    final route = routeForNotificationEvent(event);
    if (event.openedFromSystem) {
      unawaited(widget.router.push(route));
      return;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            event.body.trim().isEmpty
                ? event.title
                : '${event.title}\n${event.body}',
          ),
          action: SnackBarAction(
            label: '확인',
            onPressed: () => unawaited(widget.router.push(route)),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _AllRoundStartupSplash extends StatefulWidget {
  const _AllRoundStartupSplash({required this.child});

  final Widget child;

  @override
  State<_AllRoundStartupSplash> createState() => _AllRoundStartupSplashState();
}

class _AllRoundStartupSplashState extends State<_AllRoundStartupSplash> {
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _dismissSplashWhenReady();
  }

  /// 최소 브랜딩 시간(1800ms)을 지키되, 세션 복원(콜드스타트)이면 부서 카탈로그
  /// DB 로드 완료까지 함께 대기해 첫 화면이 kato 한글 라벨로 그려지게 한다(JY-121).
  /// 로드 지연 시 상한 3초. 미인증이면 카탈로그를 기다리지 않는다(fallback 로그인 플로우).
  Future<void> _dismissSplashWhenReady() async {
    final waits = <Future<void>>[
      Future<void>.delayed(const Duration(milliseconds: 1800)),
    ];
    if (Supabase.instance.client.auth.currentSession != null) {
      waits.add(
        DivisionCatalog.instance.whenReady
            .timeout(const Duration(milliseconds: 3000), onTimeout: () {}),
      );
    }
    await Future.wait(waits);
    if (mounted) setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // JY-121(Codex P1): 준비 완료(_visible=false) 전엔 child 를 빌드하지 않는다.
        // Stack 은 child 를 스플래시 오버레이와 동시에 빌드하므로, 그대로 두면
        // 화면들이 카탈로그 로드 전 fallback 라벨로 먼저 빌드되고, plain singleton
        // 이라 리빌드 트리거가 없어 stale kato 라벨이 남는다. child 를 로드 완료
        // 후 최초 빌드시켜 첫 프레임부터 kato 한글 라벨이 나오게 한다.
        if (!_visible) widget.child,
        IgnorePointer(
          ignoring: !_visible,
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: const Duration(milliseconds: 260),
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AllRoundLogo(
                      fontSize: 34,
                      markSize: 48,
                      textColor: Theme.of(context).colorScheme.onSurface,
                      showMark: true,
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: 32,
                      height: 7,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '내 운동 생활을 한눈에',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
