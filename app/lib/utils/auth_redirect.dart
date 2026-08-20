const mobileAuthCallback = 'kr.allround.app://login-callback/';

/// OAuth·비밀번호 재설정이 끝난 뒤 돌아올 주소를 플랫폼별로 만든다.
///
/// 웹에서 redirectTo 를 생략하면 GoTrue 는 현재 origin 이 아니라 Supabase의
/// Site URL 로 보낸다. 개발 Site URL 이 localhost:3000 으로 남아 있으면 실제
/// Flutter Web 포트와 무관한 오류 페이지로 빠지므로 현재 origin 을 명시한다.
String authRedirectTo({required bool isWeb, required Uri baseUri}) {
  if (!isWeb) return mobileAuthCallback;
  if ((baseUri.scheme != 'http' && baseUri.scheme != 'https') ||
      baseUri.host.isEmpty) {
    throw ArgumentError.value(baseUri, 'baseUri', '웹 origin 이 필요합니다.');
  }
  return '${baseUri.origin}/#/login';
}
