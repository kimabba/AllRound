import 'package:flutter_test/flutter_test.dart';
import 'package:allround/utils/google_calendar.dart';

void main() {
  test('Google 캘린더 URL은 UTC 시작·2시간 종료와 일정 정보를 담는다', () {
    final uri = buildGoogleCalendarUrl(
      title: '정기 모임',
      startsAt: DateTime.parse('2026-07-24T19:00:00+09:00'),
      description: '  풋살 정기전  ',
      location: '  광주 체육관  ',
    );

    expect(uri.host, 'calendar.google.com');
    expect(uri.path, '/calendar/render');
    expect(uri.queryParameters['action'], 'TEMPLATE');
    expect(uri.queryParameters['text'], '정기 모임');
    expect(uri.queryParameters['dates'], '20260724T100000Z/20260724T120000Z');
    expect(uri.queryParameters['details'], '풋살 정기전');
    expect(uri.queryParameters['location'], '광주 체육관');
  });

  test('빈 선택 정보는 Google 캘린더 URL에서 제외한다', () {
    final uri = buildGoogleCalendarUrl(
      title: '번개 모임',
      startsAt: DateTime.utc(2026, 7, 24, 10),
      description: ' ',
    );

    expect(uri.queryParameters, isNot(contains('details')));
    expect(uri.queryParameters, isNot(contains('location')));
  });
}
