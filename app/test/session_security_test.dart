import 'dart:async';
import 'dart:convert';

import 'package:allround/services/session_security.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('푸시 토큰 해제가 응답하지 않아도 로그아웃한다', () async {
    SharedPreferences.setMockInitialValues({});
    final neverCompletes = Completer<http.Response>();
    final client = SupabaseClient(
      'http://127.0.0.1:54321',
      'qa-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/rest/v1/rpc/unbind_my_device_tokens')) {
          return neverCompletes.future;
        }
        if (request.url.path.endsWith('/auth/v1/logout')) {
          return http.Response('', 204);
        }
        return http.Response('{}', 200);
      }),
    );
    final session = Session(
      accessToken: 'test-access-token',
      refreshToken: 'test-refresh-token',
      tokenType: 'bearer',
      expiresIn: 3600,
      user: const User(
        id: 'test-user',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '2026-08-20T00:00:00Z',
      ),
    );
    await client.auth.setInitialSession(jsonEncode(session.toJson()));

    await signOutSecurely(
      client,
      cleanupTimeout: const Duration(milliseconds: 10),
    );

    expect(client.auth.currentSession, isNull);
    expect(client.auth.currentUser, isNull);
  });
}
