import 'package:http/http.dart' as http;

/// web(admin): 기본 BrowserClient. 챗봇은 모바일 전용이라 실사용 경로는 아니나
/// import 그래프상 web 빌드에서 dart:io/cupertino_http 를 건드리지 않도록 분리.
http.Client createStreamingClientImpl() => http.Client();
