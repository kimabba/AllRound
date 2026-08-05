import 'package:allround/screens/in_app_browser_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// 웹뷰가 앱 UI 안에서 무엇을 열어도 되는지 판정하는 경계.
/// 여기가 뚫리면 사용자는 앱 화면 안에서 임의 사이트를 보게 되고
/// 피싱과 구분할 수 없다.
void main() {
  final origin = Uri.parse('https://gjtennis.kr/sub5_5.php?wr_id=123');

  test('같은 호스트 https 는 앱 안에서 연다', () {
    expect(
      inAppBrowserDecision(
        Uri.parse('https://gjtennis.kr/sub5_5.php?wr_id=456'),
        origin: origin,
      ),
      InAppNavigation.stayInApp,
    );
  });

  test('다른 호스트는 앱 안에서 열지 않고 외부 브라우저로 넘긴다', () {
    for (final url in [
      'https://evil.example/login',
      'https://gjtennis.kr.evil.example/', // 접두사만 같은 호스트
      'https://sub.gjtennis.kr/', // 서브도메인도 다른 호스트다
    ]) {
      expect(
        inAppBrowserDecision(Uri.parse(url), origin: origin),
        InAppNavigation.openExternally,
        reason: url,
      );
    }
  });

  test('같은 호스트라도 평문 http 는 앱 안에서 열지 않는다', () {
    expect(
      inAppBrowserDecision(Uri.parse('http://gjtennis.kr/x'), origin: origin),
      InAppNavigation.openExternally,
    );
  });

  test('http/https 가 아닌 스킴은 막는다', () {
    for (final url in [
      'javascript:alert(1)',
      'file:///etc/passwd',
      'intent://scan/#Intent;scheme=zxing;end',
      'kr.allround.app://login-callback/',
    ]) {
      expect(
        inAppBrowserDecision(Uri.parse(url), origin: origin),
        InAppNavigation.block,
        reason: url,
      );
    }
  });

  test('파싱 불가 URL 은 막는다', () {
    expect(inAppBrowserDecision(null, origin: origin), InAppNavigation.block);
  });
}
