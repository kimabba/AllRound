import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'router.dart';
import 'services/api.dart';
import 'services/notifications.dart'
    if (dart.library.html) 'services/notifications_web.dart';
import 'state/theme_provider.dart';
import 'theme/app_theme.dart';
import 'widgets/allround_logo.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.assertConfigured();

  await initializeDateFormatting('ko');

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  // 인증 후 FCM 등록 (실패해도 앱 진입 허용)
  Supabase.instance.client.auth.onAuthStateChange.listen((event) {
    if (event.event == AuthChangeEvent.signedIn) {
      initNotifications(ApiService(Supabase.instance.client));
    }
  });

  runApp(const ProviderScope(child: MatchUpApp()));
}

class MatchUpApp extends ConsumerWidget {
  const MatchUpApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      builder: (context, child) => _AllRoundStartupSplash(
        child: child ?? const SizedBox.shrink(),
      ),
      routerConfig: router,
    );
  }
}

class _AllRoundStartupSplash extends StatefulWidget {
  const _AllRoundStartupSplash({required this.child});

  final Widget child;

  @override
  State<_AllRoundStartupSplash> createState() => _AllRoundStartupSplashState();
}

class _AllRoundStartupSplashState extends State<_AllRoundStartupSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();
    Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        IgnorePointer(
          ignoring: !_visible,
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: const Duration(milliseconds: 260),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final raw = _controller.value;
                final ballProgress =
                    Curves.easeInCubic.transform((raw / 0.58).clamp(0, 1));
                final impactProgress = Curves.easeOutCubic
                    .transform(((raw - 0.46) / 0.36).clamp(0, 1));
                final logoProgress = Curves.easeOutBack
                    .transform(((raw - 0.58) / 0.36).clamp(0, 1));
                final size = MediaQuery.sizeOf(context);
                final impact = Offset(size.width * 0.5, size.height * 0.45);
                final ballStart = Offset(size.width * -0.18, size.height * 0.2);
                final ballEnd = impact;
                final ball = Offset.lerp(ballStart, ballEnd, ballProgress)!;

                return ColoredBox(
                  color: const Color(0xFF0F1D47),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _SportImpactPainter(
                            ball: ball,
                            impact: impact,
                            ballProgress: ballProgress,
                            impactProgress: impactProgress,
                          ),
                        ),
                      ),
                      Center(
                        child: Opacity(
                          opacity: logoProgress.clamp(0, 1),
                          child: Transform.scale(
                            scale: 0.92 + (0.08 * logoProgress),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const AllRoundLogo(
                                  fontSize: 34,
                                  markSize: 58,
                                  textColor: Colors.white,
                                  showMark: true,
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  '내 운동 생활을 한눈에',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                        color: Colors.white
                                            .withValues(alpha: 0.76),
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _SportImpactPainter extends CustomPainter {
  const _SportImpactPainter({
    required this.ball,
    required this.impact,
    required this.ballProgress,
    required this.impactProgress,
  });

  final Offset ball;
  final Offset impact;
  final double ballProgress;
  final double impactProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final trailPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFFB9E769).withValues(alpha: 0),
          const Color(0xFFB9E769).withValues(alpha: 0.38),
          Colors.white.withValues(alpha: 0.72),
        ],
      ).createShader(Rect.fromPoints(Offset.zero, ball))
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final trailStart = Offset(
      ball.dx - 150 * (0.4 + ballProgress),
      ball.dy - 58 * (0.4 + ballProgress),
    );
    canvas.drawLine(trailStart, ball, trailPaint);

    if (impactProgress > 0) {
      final shockPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withValues(alpha: 0.34 * (1 - impactProgress));
      canvas.drawCircle(impact, 36 + 170 * impactProgress, shockPaint);

      final glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..color = const Color(0xFFB9E769)
            .withValues(alpha: 0.16 * (1 - impactProgress))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawCircle(impact, 28 + 142 * impactProgress, glowPaint);

      final crackPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.46 * (1 - impactProgress))
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round;
      const angles = [-2.8, -2.16, -1.52, -0.82, -0.26, 0.42, 1.1, 1.88];
      for (var i = 0; i < angles.length; i++) {
        final angle = angles[i];
        final length = (44 + i * 9) * impactProgress;
        final bend = Offset(
          math.cos(angle + 0.28) * length * 0.34,
          math.sin(angle + 0.28) * length * 0.34,
        );
        final start =
            impact + Offset(math.cos(angle) * 18, math.sin(angle) * 18);
        final end =
            impact + Offset(math.cos(angle) * length, math.sin(angle) * length);
        final path = Path()
          ..moveTo(start.dx, start.dy)
          ..lineTo(start.dx + bend.dx, start.dy + bend.dy)
          ..lineTo(end.dx, end.dy);
        canvas.drawPath(path, crackPaint);
      }
    }

    final ballOpacity = (1 - impactProgress).clamp(0, 1).toDouble();
    final ballPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.35, -0.35),
        colors: [Color(0xFFFFFFFF), Color(0xFFD9F66F), Color(0xFF7AB719)],
      ).createShader(Rect.fromCircle(center: ball, radius: 31))
      ..color = Colors.white.withValues(alpha: ballOpacity);
    canvas.saveLayer(
      Rect.fromCircle(center: ball, radius: 40),
      Paint()..color = Colors.white.withValues(alpha: ballOpacity),
    );
    canvas.drawCircle(ball, 31, ballPaint);

    final seamPaint = Paint()
      ..color = const Color(0xFF0F1D47).withValues(alpha: 0.38)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: ball + const Offset(-4, 0), radius: 22),
      -math.pi / 2,
      math.pi,
      false,
      seamPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: ball + const Offset(9, 0), radius: 22),
      math.pi / 2,
      math.pi,
      false,
      seamPaint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SportImpactPainter oldDelegate) {
    return oldDelegate.ball != ball ||
        oldDelegate.impact != impact ||
        oldDelegate.ballProgress != ballProgress ||
        oldDelegate.impactProgress != impactProgress;
  }
}
