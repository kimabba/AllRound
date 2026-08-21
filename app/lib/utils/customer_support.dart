import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const customerSupportEmail = 'play@jyoungad.kr';

enum CustomerSupportOpenResult {
  opened,
  addressCopied,
  unavailable,
}

typedef CustomerSupportUriLauncher = Future<bool> Function(Uri uri);
typedef CustomerSupportClipboardWriter = Future<void> Function(
  ClipboardData data,
);

Future<bool> _launchCustomerSupportUri(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

Future<CustomerSupportOpenResult> openCustomerSupportEmail({
  CustomerSupportUriLauncher launcher = _launchCustomerSupportUri,
  CustomerSupportClipboardWriter clipboardWriter = Clipboard.setData,
}) async {
  final uri = Uri(
    scheme: 'mailto',
    path: customerSupportEmail,
    queryParameters: const {'subject': '올라운드 고객센터 문의'},
  );

  try {
    if (await launcher(uri)) {
      return CustomerSupportOpenResult.opened;
    }
  } on Exception {
    // 메일 앱이 없거나 플랫폼 호출이 실패해도 아래 복사 동작을 제공한다.
  }

  try {
    await clipboardWriter(const ClipboardData(text: customerSupportEmail));
    return CustomerSupportOpenResult.addressCopied;
  } on Exception {
    return CustomerSupportOpenResult.unavailable;
  }
}
