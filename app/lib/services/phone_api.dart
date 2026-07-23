import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_base.dart';

/// 전화번호 SMS OTP 인증 API (send-otp / verify-otp Edge Function).
///
/// 서버가 이미 한국어 에러 메시지를 내려주므로(예: rate limit, 중복번호),
/// 실패 시 그 메시지를 그대로 [ApiException] 으로 올려 UI 가 표시한다.
mixin PhoneApi on ApiBase {
  /// 인증번호(SMS) 발송. 인증된 사용자만 호출 가능.
  Future<void> sendOtp(String phone) async {
    final res = await httpPost(
      uri('send-otp'),
      headers: await authHeaders(),
      body: jsonEncode({'phone': phone}),
    );
    _ensureOk(res);
  }

  /// 인증번호 검증. 성공 시 현재 계정에 번호가 기록된다.
  Future<void> verifyOtp(String phone, String code) async {
    final res = await httpPost(
      uri('verify-otp'),
      headers: await authHeaders(),
      body: jsonEncode({'phone': phone, 'code': code}),
    );
    _ensureOk(res);
  }

  void _ensureOk(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    var message = '요청을 처리하지 못했습니다. 잠시 후 다시 시도해주세요.';
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['error'] is String) message = body['error'] as String;
    } catch (_) {
      // 응답 파싱 실패 시 기본 메시지 유지.
    }
    throw ApiException(message);
  }
}
