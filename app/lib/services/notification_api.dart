import '../models/app_notification.dart';
import 'api_base.dart';

/// 알림·디바이스 토큰 API.
mixin NotificationApi on ApiBase {
  Future<void> registerDeviceToken(String token, String platform) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    await supabase.rpc('bind_my_device_token', params: {
      'p_token': token,
      'p_platform': platform,
    });
  }

  Future<void> setDeviceTokenSound(String token, bool enabled) async {
    if (supabase.auth.currentUser == null) return;
    await supabase.rpc('set_my_device_token_sound', params: {
      'p_token': token,
      'p_sound_enabled': enabled,
    });
  }

  Future<void> unregisterDeviceTokens() async {
    if (supabase.auth.currentUser == null) return;
    await supabase.rpc('unbind_my_device_tokens');
  }

  Future<List<AppNotification>> myNotifications({int limit = 50}) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return const [];
    final rows = await supabase
        .from('notifications')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map((r) => AppNotification.fromJson(r)).toList();
  }

  Future<int> unreadNotificationCount() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return 0;
    final res = await supabase
        .from('notifications')
        .select('id')
        .eq('user_id', userId)
        .eq('is_read', false);
    return (res as List).length;
  }

  Future<void> markNotificationRead(String id) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    await supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('id', id)
        .eq('user_id', userId);
  }

  Future<void> markAllNotificationsRead() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    await supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', userId)
        .eq('is_read', false);
  }
}
