import '../models/app_notification.dart';
import 'api_base.dart';

/// 알림·디바이스 토큰 API.
mixin NotificationApi on ApiBase {
  Future<void> registerDeviceToken(String token, String platform) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    await supabase.from('device_tokens').upsert({
      'user_id': userId,
      'token': token,
      'platform': platform,
      'enabled': true,
    });
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
    await supabase
        .from('notifications')
        .update({'is_read': true}).eq('id', id);
  }

  Future<void> markAllNotificationsRead() async {
    await supabase
        .from('notifications')
        .update({'is_read': true}).eq('is_read', false);
  }
}
