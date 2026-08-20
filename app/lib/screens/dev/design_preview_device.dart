import 'package:flutter/material.dart';

enum DesignPreviewDevice {
  phone320(
    queryValue: '320',
    label: '작은 화면 · 320 × 568',
    size: Size(320, 568),
    safeArea: EdgeInsets.only(top: 20),
  ),
  phone390(
    queryValue: '390',
    label: 'iPhone · 390 × 844',
    size: Size(390, 844),
    safeArea: EdgeInsets.only(top: 47, bottom: 34),
  ),
  android412(
    queryValue: 'android-412',
    label: 'Android · 412 × 915',
    size: Size(412, 915),
    safeArea: EdgeInsets.only(top: 24, bottom: 24),
  ),
  phone430(
    queryValue: '430',
    label: 'iPhone Pro Max · 430 × 932',
    size: Size(430, 932),
    safeArea: EdgeInsets.only(top: 59, bottom: 34),
  );

  const DesignPreviewDevice({
    required this.queryValue,
    required this.label,
    required this.size,
    required this.safeArea,
  });

  final String queryValue;
  final String label;
  final Size size;
  final EdgeInsets safeArea;

  static DesignPreviewDevice? fromUri(Uri uri) {
    final value = uri.queryParameters['designDevice'];
    for (final device in values) {
      if (device.queryValue == value) return device;
    }
    return null;
  }

  String locationFor(String route, {required bool dark}) {
    final uri = Uri.parse(route);
    final queryParameters = <String, String>{
      ...uri.queryParameters,
      'designDevice': queryValue,
      'designTheme': dark ? 'dark' : 'light',
    };
    return uri.replace(queryParameters: queryParameters).toString();
  }
}
