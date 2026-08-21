import 'package:allround/utils/customer_support.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('메일 앱을 열면 복사하지 않는다', () async {
    ClipboardData? copiedData;

    final result = await openCustomerSupportEmail(
      launcher: (uri) async {
        expect(uri.scheme, 'mailto');
        expect(uri.path, customerSupportEmail);
        expect(uri.queryParameters['subject'], '올라운드 고객센터 문의');
        return true;
      },
      clipboardWriter: (data) async => copiedData = data,
    );

    expect(result, CustomerSupportOpenResult.opened);
    expect(copiedData, isNull);
  });

  test('메일 앱이 없으면 고객센터 주소를 복사한다', () async {
    ClipboardData? copiedData;

    final result = await openCustomerSupportEmail(
      launcher: (_) async => false,
      clipboardWriter: (data) async => copiedData = data,
    );

    expect(result, CustomerSupportOpenResult.addressCopied);
    expect(copiedData?.text, customerSupportEmail);
  });

  test('메일 앱 호출에서 예외가 나도 고객센터 주소를 복사한다', () async {
    ClipboardData? copiedData;

    final result = await openCustomerSupportEmail(
      launcher: (_) async => throw PlatformException(code: 'no_handler'),
      clipboardWriter: (data) async => copiedData = data,
    );

    expect(result, CustomerSupportOpenResult.addressCopied);
    expect(copiedData?.text, customerSupportEmail);
  });

  test('메일 앱과 클립보드가 모두 실패하면 안내 가능한 상태를 반환한다', () async {
    final result = await openCustomerSupportEmail(
      launcher: (_) async => false,
      clipboardWriter: (_) async => throw Exception('clipboard unavailable'),
    );

    expect(result, CustomerSupportOpenResult.unavailable);
  });
}
