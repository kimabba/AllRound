import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('디자인 월이 주요 사용자 화면과 프리뷰 조건을 유지한다', () {
    final wall = File(
      'lib/screens/dev/design_wall_screen.dart',
    ).readAsStringSync();
    final router = File('lib/router.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    for (final route in [
      '/',
      '/tournaments',
      '/clubs',
      '/profile',
      '/notifications',
      '/login',
      '/onboarding',
    ]) {
      expect(wall, contains("route: '$route'"));
    }

    expect(router, contains("path: '/design'"));
    expect(router,
        contains('final userDesignPreview = AppConfig.userDesignPreview;'));
    expect(
      router,
      contains('final webUserDesignPreview = kIsWeb && userDesignPreview;'),
    );
    expect(router, contains("loc == '/design' && !webUserDesignPreview"));
    expect(
      router,
      isNot(
        contains(
          'final userDesignPreview = kIsWeb && AppConfig.userDesignPreview;',
        ),
      ),
    );
    expect(main, contains("path == '/design'"));
    expect(main, contains('DesignPreviewDevice.fromUri(routeUri)'));
    expect(main, contains('final isAdminSurface ='));
    expect(main, contains('if (!kIsWeb || isDesignWall || isAdminSurface)'));
    expect(
      main,
      isNot(contains('!AppConfig.userDesignPreview || isDesignWall')),
    );
    expect(wall, contains('IgnorePointer'));
    expect(wall, contains('device.safeArea'));
    expect(wall, contains('전체 화면·스크롤'));
    expect(wall, contains('OverflowBox'));
    expect(wall, contains('width: displayWidth'));
    expect(wall, contains("route: '/clubs/preview-tennis-01'"));
    expect(
      wall,
      contains("club: clubDesignPreviewById('preview-tennis-01')!"),
    );
    expect(wall, isNot(contains('preview-club-tennis')));
    expect(wall, isNot(contains('SliverGridDelegateWithMaxCrossAxisExtent')));
    expect(wall, isNot(contains('? 300.0 : 248.0')));
  });
}
