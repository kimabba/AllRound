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
}) async {
  final userId = supabase.auth.currentUser?.id;
  try {
    await ApiService(supabase).unregisterDeviceTokens();
  } catch (_) {
    // Session termination must remain available offline.
  }
  if (userId != null) {
    await clearLocalUserPreferences(userId);
  }
  await supabase.auth.signOut(scope: scope);
}
