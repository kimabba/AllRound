import 'package:supabase_flutter/supabase_flutter.dart';

import 'api.dart';
import 'local_user_preferences.dart';

/// Unbinds push destinations before ending the authenticated session.
///
/// Sign-out still proceeds if the network is unavailable. The server-side
/// bind RPC also transfers a physical token to the next authenticated user,
/// preventing stale cross-account delivery when that user signs in.
Future<void> signOutSecurely(
  SupabaseClient supabase, {
  SignOutScope scope = SignOutScope.global,
  Duration cleanupTimeout = const Duration(seconds: 1),
}) async {
  final userId = supabase.auth.currentUser?.id;
  try {
    // 로컬 Supabase가 꺼져 있거나 네트워크가 끊긴 경우 RPC가 오래 대기해도
    // 실제 세션 종료까지 막으면 안 된다.
    await ApiService(supabase).unregisterDeviceTokens().timeout(cleanupTimeout);
  } catch (_) {
    // Session termination must remain available offline.
  }
  if (userId != null) {
    await clearLocalUserPreferences(userId);
  }
  await supabase.auth.signOut(scope: scope);
}
