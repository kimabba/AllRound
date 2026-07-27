import 'package:flutter_test/flutter_test.dart';
import 'package:allround/widgets/clubs/club_filter_widgets.dart';

void main() {
  test('모집 중 필터는 통합 필터 상태와 라벨에 반영된다', () {
    const initial = ClubSearchFilters();

    expect(initial.hasActive, isFalse);
    expect(initial.labels, isNot(contains('모집 중')));

    final recruiting = initial.copyWith(recruitingOnly: true);

    expect(recruiting.hasActive, isTrue);
    expect(recruiting.labels, contains('모집 중'));
    expect(recruiting.cleared().recruitingOnly, isFalse);
  });
}
