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
    final rows = await supabase
        .from('notifications')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map((r) => AppNotification.fromJson(r)).toList();
  }

  Future<int> unreadNotificationCount() async {
    final res =
        await supabase.from('notifications').select('id').eq('is_read', false);
    return (res as List).length;
  }

  Future<void> markNotificationRead(String id) async {
    await supabase.from('notifications').update({'is_read': true}).eq('id', id);
  }

  Future<void> markAllNotificationsRead() async {
    await supabase
        .from('notifications')
        .update({'is_read': true}).eq('is_read', false);
  }
}
