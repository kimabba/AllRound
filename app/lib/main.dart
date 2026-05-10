import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'router.dart';
import 'services/api.dart';
import 'services/notifications.dart';
import 'state/theme_provider.dart';
import 'theme/app_theme.dart';

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
      title: 'Match-up',
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
      routerConfig: router,
    );
  }
}
