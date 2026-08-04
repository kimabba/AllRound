import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme/tokens.dart';

/// 웹뷰 안에서 이동 요청을 어떻게 처리할지.
enum InAppNavigation { stayInApp, openExternally, block }

/// 공고를 연 그 출처(https + 같은 호스트) 안에서만 앱 안에 머문다.
///
/// 협회 사이트가 다른 곳으로 보내면(30x 리다이렉트 포함) 앱 UI 를 두른 채
/// 임의 사이트를 보여주게 되고, 그러면 사용자는 피싱과 구분할 수 없다.
/// 그런 이동은 주소창이 보이는 기본 브라우저로 넘긴다.
/// http/https 가 아닌 스킴(`javascript:` `file:` `intent:` 등)은 그냥 막는다.
InAppNavigation inAppBrowserDecision(Uri? target, {required Uri origin}) {
  if (target == null) return InAppNavigation.block;
  if (target.scheme == 'https' && target.host == origin.host) {
    return InAppNavigation.stayInApp;
  }
  if (target.scheme == 'https' || target.scheme == 'http') {
    return InAppNavigation.openExternally;
  }
  return InAppNavigation.block;
}

/// Opens an external tournament announcement inside the app.
///
/// The native WebView keeps the user in the app while the explicit close
/// action returns to the tournament detail screen that opened it.
class InAppBrowserScreen extends StatefulWidget {
  const InAppBrowserScreen({super.key, required this.uri});

  final Uri uri;

  @override
  State<InAppBrowserScreen> createState() => _InAppBrowserScreenState();
}

class _InAppBrowserScreenState extends State<InAppBrowserScreen> {
  late final WebViewController _controller;
  int _progress = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController(
      // 읽기 전용 뷰어다. 카메라·마이크·위치를 줄 이유가 없다.
      // Android 구현은 기본 거부지만 iOS WKWebView 는 기본이 "사용자에게 묻기"라
      // 명시하지 않으면 임의 페이지가 권한 창을 띄운다.
      onPermissionRequest: (request) => request.deny(),
    )
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (!mounted) return;
            setState(() => _progress = progress);
          },
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _loading = true;
              _error = null;
            });
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _progress = 100;
            });
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame != true || !mounted) return;
            setState(() {
              _loading = false;
              _error = '공고 페이지를 불러오지 못했어요.';
            });
          },
          onNavigationRequest: (request) {
            final target = Uri.tryParse(request.url);
            switch (inAppBrowserDecision(target, origin: widget.uri)) {
              case InAppNavigation.stayInApp:
                return NavigationDecision.navigate;
              case InAppNavigation.openExternally:
                unawaited(
                  launchUrl(target!, mode: LaunchMode.externalApplication),
                );
                return NavigationDecision.prevent;
              case InAppNavigation.block:
                return NavigationDecision.prevent;
            }
          },
        ),
      )
      ..loadRequest(widget.uri);
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _progress = 0;
    });
    await _controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '닫기',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('원본 공고'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _reload,
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_error != null)
            _BrowserError(onRetry: _reload)
          else
            WebViewWidget(controller: _controller),
          if (_loading && _error == null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                value:
                    _progress == 0 || _progress >= 100 ? null : _progress / 100,
                color: cs.primary,
                minHeight: 2,
              ),
            ),
        ],
      ),
    );
  }
}

class _BrowserError extends StatelessWidget {
  const _BrowserError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.public_off_outlined,
                size: 40, color: cs.onSurfaceVariant),
            const SizedBox(height: AppSpacing.md),
            Text(
              '공고 페이지를 불러오지 못했어요.',
              textAlign: TextAlign.center,
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '네트워크를 확인한 뒤 다시 시도해 주세요.',
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}
