import 'package:allround/utils/auth_redirect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('웹 OAuth 는 현재 실행 origin 의 로그인 화면으로 돌아온다', () {
    expect(
      authRedirectTo(
        isWeb: true,
        baseUri: Uri.parse(
          'http://127.0.0.1:7357/?preview=editorial-bright-v1#/login',
        ),
      ),
      'http://127.0.0.1:7357/#/login',
    );
  });

  test('운영 웹에서도 기존 path와 query를 OAuth 복귀 주소에 섞지 않는다', () {
    expect(
      authRedirectTo(
        isWeb: true,
        baseUri: Uri.parse('https://allround.example/clubs?secret=no'),
      ),
      'https://allround.example/#/login',
    );
  });

  test('모바일 OAuth 는 등록된 앱 딥링크로 돌아온다', () {
    expect(
      authRedirectTo(isWeb: false, baseUri: Uri()),
      mobileAuthCallback,
    );
  });
}
