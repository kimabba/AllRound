import 'package:allround/screens/dev/design_preview_device.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('디자인 프리뷰 기기는 대표 화면 크기와 안전 영역을 제공한다', () {
    expect(DesignPreviewDevice.phone320.size, const Size(320, 568));
    expect(DesignPreviewDevice.phone320.safeArea.top, 20);

    expect(DesignPreviewDevice.phone390.size, const Size(390, 844));
    expect(DesignPreviewDevice.phone390.safeArea.top, 47);
    expect(DesignPreviewDevice.phone390.safeArea.bottom, 34);

    expect(DesignPreviewDevice.android412.size, const Size(412, 915));
    expect(DesignPreviewDevice.android412.safeArea.top, 24);
    expect(DesignPreviewDevice.android412.safeArea.bottom, 24);

    expect(DesignPreviewDevice.phone430.size, const Size(430, 932));
    expect(DesignPreviewDevice.phone430.safeArea.top, 59);
    expect(DesignPreviewDevice.phone430.safeArea.bottom, 34);
  });

  test('선택 기기와 테마를 개별 화면 주소에 유지한다', () {
    final location = DesignPreviewDevice.phone430.locationFor(
      '/tournaments?search=1',
      dark: true,
    );
    final uri = Uri.parse(location);

    expect(uri.path, '/tournaments');
    expect(uri.queryParameters['search'], '1');
    expect(uri.queryParameters['designDevice'], '430');
    expect(uri.queryParameters['designTheme'], 'dark');
    expect(DesignPreviewDevice.fromUri(uri), DesignPreviewDevice.phone430);
  });

  test('알 수 없는 프리뷰 기기는 적용하지 않는다', () {
    expect(
      DesignPreviewDevice.fromUri(Uri.parse('/?designDevice=999')),
      isNull,
    );
  });
}
