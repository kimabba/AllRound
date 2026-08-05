import 'dart:io' show Platform;

import 'package:cupertino_http/cupertino_http.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// iOS/macOS: URLSession 기반 CupertinoClient (SSE 스트리밍 정상).
/// 그 외(android 등): 기존 IOClient 유지.
http.Client createStreamingClientImpl() {
  if (Platform.isIOS || Platform.isMacOS) {
    return CupertinoClient.defaultSessionConfiguration();
  }
  return IOClient();
}
