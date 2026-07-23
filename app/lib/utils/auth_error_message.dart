import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import 'age.dart';

/// Supabase AuthException 영어 원문을 사용자용 한국어로 매핑한다.
///
/// 로그인 화면에서 분리해 둔 이유는 테스트 가능하게 만들기 위해서다. 이 매핑은
/// GoTrue 가 보내는 영문 문구에 의존하므로, 서버 문구가 바뀌면 조용히 깨진다.
/// 실제로 유출 비밀번호 응답이 그렇게 새어 제네릭 문구가 노출된 적이 있다(#270).
/// `test/auth_error_message_test.dart` 가 실측 응답으로 그 회귀를 막는다.
///
/// [signUp] 은 매칭이 하나도 없을 때 회원가입/로그인 중 어느 문구를 낼지 정한다.
String authErrorMessage(AuthException e, {required bool signUp}) {
  final m = e.message.toLowerCase();
  if (m.contains('invalid login') || m.contains('invalid credentials')) {
    return '이메일 또는 비밀번호가 올바르지 않습니다.';
  }
  if (m.contains('already registered') || m.contains('already exists')) {
    return '이미 가입된 이메일입니다. 로그인해 주세요.';
  }
  if (m.contains('email not confirmed')) {
    return '이메일 인증이 필요합니다. 메일함을 확인해 주세요.';
  }
  if (m.contains('rate limit') || m.contains('too many')) {
    return '요청이 많습니다. 잠시 후 다시 시도해 주세요.';
  }
  // 유출/취약 비밀번호(HaveIBeenPwned). GoTrue 실제 문구는
  // "known to be weak and easy to guess"라 기존 'weak password' 문자열
  // 매칭이 빗나가 generic 폴백으로 떨어졌다. error_code 로 견고하게 잡는다.
  if (e.code == 'weak_password' ||
      m.contains('weak password') ||
      m.contains('known to be weak') ||
      m.contains('easy to guess') ||
      m.contains('pwned') ||
      m.contains('password should')) {
    return '사용할 수 없는 비밀번호예요. 유출되었거나 너무 단순한 비밀번호이니 '
        '다른 비밀번호로 바꿔 주세요.';
  }
  if (m.contains('birth_date_required')) {
    return '계정 생성 전에 생년월일을 확인해 주세요.';
  }
  if (m.contains('invalid_birth_date')) {
    return '올바른 생년월일을 입력해 주세요.';
  }
  if (m.contains('minor_not_allowed')) {
    return '만 $kMinSignupAge세 이상만 가입할 수 있습니다.';
  }
  if (m.contains('google_signup_disabled')) {
    return '신규 가입은 이메일로 진행해 주세요.';
  }
  if (m.contains('signups not allowed') || m.contains('disabled')) {
    return '현재 회원가입이 제한되어 있습니다.';
  }
  return signUp
      ? '회원가입에 실패했습니다. 잠시 후 다시 시도해 주세요.'
      : '로그인에 실패했습니다. 잠시 후 다시 시도해 주세요.';
}

/// 비밀번호 재설정 화면(updateUser)용 매핑.
///
/// 기존엔 이 화면이 `authErrorMessage` 를 쓰지 않고 `should be different` 외
/// 모든 오류를 "링크가 만료됐다면 다시 요청" 으로 뭉갰다. 그 결과 유출/취약
/// 비밀번호(422 weak_password)까지 링크 만료로 오안내돼, 링크가 멀쩡한데도
/// 사용자가 링크를 다시 받으러 가는 헛수고를 했다(2026-07-23 실측).
///
/// 취약 비번·기타 표준 오류는 공용 매핑을 재사용하고, 재설정 문맥에서만
/// 의미 있는 두 가지(이전과 동일한 비번, 그리고 세션/토큰 만료성 실패)는
/// 여기서 따로 안내한다.
String resetPasswordErrorMessage(AuthException e) {
  final m = e.message.toLowerCase();
  // 새 비번이 이전과 같은 경우. authErrorMessage 는 'password should' 부분일치로
  // 이 문구를 취약 비번으로 오분류하므로 반드시 먼저 가른다.
  if (e.code == 'same_password' || m.contains('should be different')) {
    return '이전과 다른 비밀번호로 설정해 주세요.';
  }
  final mapped = authErrorMessage(e, signUp: false);
  // 구체 매핑이 없어 로그인용 제네릭 폴백이 나왔다면, 재설정 화면에서는
  // 링크 재요청 안내가 더 정확하다(세션/토큰 만료 등).
  if (mapped == '로그인에 실패했습니다. 잠시 후 다시 시도해 주세요.') {
    return '재설정에 실패했습니다. 링크가 만료됐다면 다시 요청해 주세요.';
  }
  return mapped;
}
