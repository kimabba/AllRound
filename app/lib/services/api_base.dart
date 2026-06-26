import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

/// Edge Function REST 호출에 필요한 공통 헬퍼.
///
/// 도메인별 mixin 이 `on ApiBase` 로 접근한다.
class ApiBase {
  ApiBase(this.supabase);

  final SupabaseClient supabase;

  Future<Map<String, String>> authHeaders() async {
    final session = supabase.auth.currentSession;
    String? token = session?.accessToken;
    if (session != null && session.isExpired) {
      final refreshed = await supabase.auth.refreshSession();
      token = refreshed.session?.accessToken;
    }
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Uri uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(AppConfig.apiBaseUrl);
    return base.replace(
      path: '${base.path}/$path',
      queryParameters: query?..removeWhere((_, v) => v.isEmpty),
    );
  }

  void check(http.Response res) {
    if (res.statusCode >= 400) {
      throw Exception('${res.statusCode}: ${res.body}');
    }
  }
}
