import 'package:http/http.dart' as http;

import 'chat_client_io.dart'
    if (dart.library.js_interop) 'chat_client_web.dart';

/// SSE 스트리밍용 HTTP 클라이언트를 플랫폼별로 생성한다.
///
/// iOS/macOS 의 `dart:io` HttpClient 는 `text/event-stream` 응답의 첫 청크
/// 이후 후속 데이터를 실시간으로 흘려주지 못해(버퍼링), 챗봇 답변이 첫 이벤트
/// 이후 멈추는 문제가 있었다. iOS/macOS 는 URLSession 기반 CupertinoClient 로
/// 교체해 네이티브 스트리밍을 사용한다. (web/android 는 기존 동작 유지)
http.Client createStreamingClient() => createStreamingClientImpl();
