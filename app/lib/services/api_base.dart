import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

/// 네트워크/타임아웃 등 사용자에게 보여줄 수 있는 API 에러.
class ApiException implements Exception {
  ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Edge Function REST 호출에 필요한 공통 헬퍼.
///
/// 도메인별 mixin 이 `on ApiBase` 로 접근한다.
class ApiBase {
  ApiBase(this.supabase);

  static const _timeout = Duration(seconds: 30);

  final SupabaseClient supabase;

  Future<Map<String, String>> authHeaders() async {
    final session = supabase.auth.currentSession;
    String? token = session?.accessToken;
    if (session != null && session.isExpired) {
      try {
        final refreshed = await supabase.auth.refreshSession();
        token = refreshed.session?.accessToken;
      } catch (_) {
        // 리프레시 실패 시 기존 토큰 유지 (만료됐으면 서버가 401 반환)
      }
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

  /// HTTP GET with timeout + 네트워크 에러 처리.
  Future<http.Response> httpGet(Uri url,
      {Map<String, String>? headers}) async {
    try {
      return await http.get(url, headers: headers).timeout(_timeout);
    } on TimeoutException {
      throw ApiException('서버 응답이 없습니다. 잠시 후 다시 시도해주세요.');
    } on http.ClientException {
      throw ApiException('네트워크 연결을 확인해주세요.');
    }
  }

  /// HTTP POST with timeout + 네트워크 에러 처리.
  Future<http.Response> httpPost(Uri url,
      {Map<String, String>? headers, Object? body}) async {
    try {
      return await http
          .post(url, headers: headers, body: body)
          .timeout(_timeout);
    } on TimeoutException {
      throw ApiException('서버 응답이 없습니다. 잠시 후 다시 시도해주세요.');
    } on http.ClientException {
      throw ApiException('네트워크 연결을 확인해주세요.');
    }
  }

  void check(http.Response res) {
    if (res.statusCode >= 400) {
      throw Exception('${res.statusCode}: ${res.body}');
    }
  }
}
