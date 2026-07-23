import 'package:allround/utils/age.dart';
import 'package:allround/utils/auth_error_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

/// message/code 쌍은 실제 GoTrue 응답 본문에서 그대로 옮긴 값이다
/// (프로젝트 `auth/v1/signup` 직접 호출로 확인, 2026-07-22).
void main() {
  group('유출/취약 비밀번호 (#270 회귀 방지)', () {
    // 이 문구에는 'weak password' 도 'password should' 도 들어있지 않다.
    // 문자열만으로 분기하던 시절 제네릭 폴백으로 새던 바로 그 응답이다.
    const pwnedMessage =
        'Password is known to be weak and easy to guess, please choose a different one.';
    const expected = '사용할 수 없는 비밀번호예요. 유출되었거나 너무 단순한 비밀번호이니 '
        '다른 비밀번호로 바꿔 주세요.';

    test('error_code 로 잡는다', () {
      final e = AuthException(pwnedMessage,
          statusCode: '422', code: 'weak_password');
      expect(authErrorMessage(e, signUp: true), expected);
    });

    test('code 가 비어 와도 문구로 잡는다', () {
      // 구버전 GoTrue 등 error_code 가 없는 경로 대비 폴백.
      final e = AuthException(pwnedMessage, statusCode: '422');
      expect(authErrorMessage(e, signUp: true), expected);
    });

    test('정책 위반 문구(password should)도 같은 안내로 간다', () {
      final e = AuthException(
          'Password should be at least 6 characters.',
          statusCode: '422',
          code: 'weak_password');
      expect(authErrorMessage(e, signUp: true), expected);
    });
  });

  group('GoTrue 표준 오류', () {
    test('이미 가입된 이메일', () {
      final e = AuthException('User already registered',
          statusCode: '422', code: 'user_already_exists');
      expect(authErrorMessage(e, signUp: true), '이미 가입된 이메일입니다. 로그인해 주세요.');
    });

    test('잘못된 로그인 정보', () {
      final e = AuthException('Invalid login credentials',
          statusCode: '400', code: 'invalid_credentials');
      expect(
        authErrorMessage(e, signUp: false),
        '이메일 또는 비밀번호가 올바르지 않습니다.',
      );
    });
  });

  group('커스텀 훅 오류', () {
    // 문구 정본: supabase/migrations/20260719010238_enforce_pre_account_age.sql
    // 훅이 낸 오류는 error_code 가 'unknown' 으로 와서 문구로만 판별된다.
    test('미성년 거부', () {
      final e = AuthException('MINOR_NOT_ALLOWED: 만 14세 이상만 가입할 수 있습니다.',
          statusCode: '403', code: 'unknown');
      expect(
        authErrorMessage(e, signUp: true),
        '만 $kMinSignupAge세 이상만 가입할 수 있습니다.',
      );
    });

    test('생년월일 누락', () {
      final e = AuthException(
          'BIRTH_DATE_REQUIRED: 계정 생성 전에 생년월일을 확인해 주세요.',
          statusCode: '400',
          code: 'unknown');
      expect(authErrorMessage(e, signUp: true), '계정 생성 전에 생년월일을 확인해 주세요.');
    });

    test('구글 신규가입 차단', () {
      final e = AuthException(
          'GOOGLE_SIGNUP_DISABLED: 신규 가입은 이메일로 진행해 주세요.',
          statusCode: '403',
          code: 'unknown');
      expect(authErrorMessage(e, signUp: true), '신규 가입은 이메일로 진행해 주세요.');
    });
  });

  group('폴백', () {
    test('매핑 없는 오류는 가입/로그인 문맥에 따라 갈린다', () {
      final e = AuthException('Something unexpected', statusCode: '500');
      expect(
        authErrorMessage(e, signUp: true),
        '회원가입에 실패했습니다. 잠시 후 다시 시도해 주세요.',
      );
      expect(
        authErrorMessage(e, signUp: false),
        '로그인에 실패했습니다. 잠시 후 다시 시도해 주세요.',
      );
    });
  });

  group('비밀번호 재설정 화면 매핑', () {
    const weakExpected = '사용할 수 없는 비밀번호예요. 유출되었거나 너무 단순한 비밀번호이니 '
        '다른 비밀번호로 바꿔 주세요.';
    const linkExpected = '재설정에 실패했습니다. 링크가 만료됐다면 다시 요청해 주세요.';

    test('유출 비밀번호(422 pwned)는 링크 만료가 아니라 취약 비번 안내로 간다', () {
      // 실제 재설정 실패의 근본 원인(2026-07-23 로그): updateUser 가 422 weak_password 로 떨어졌다.
      final e = AuthException(
          'Password is known to be weak and easy to guess, please choose a different one.',
          statusCode: '422',
          code: 'weak_password');
      expect(resetPasswordErrorMessage(e), weakExpected);
    });

    test('길이 정책 위반도 취약 비번 안내로 간다', () {
      final e = AuthException('Password should be at least 6 characters.',
          statusCode: '422', code: 'weak_password');
      expect(resetPasswordErrorMessage(e), weakExpected);
    });

    test('새 비번이 이전과 같으면 별도 안내(취약 비번 오분류 방지)', () {
      final e = AuthException(
          'New password should be different from the old password.',
          statusCode: '422',
          code: 'same_password');
      expect(resetPasswordErrorMessage(e), '이전과 다른 비밀번호로 설정해 주세요.');
    });

    test('그 밖의 알 수 없는 실패는 링크 재요청을 안내한다', () {
      final e = AuthException('Something unexpected', statusCode: '500');
      expect(resetPasswordErrorMessage(e), linkExpected);
    });
  });
}
