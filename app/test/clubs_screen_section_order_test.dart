import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('모임 화면은 검색·나의 모임·주변·모집·추천 순서로 구성된다', () {
    final source = File('lib/screens/clubs_screen.dart').readAsStringSync();
    final buildStart = source.indexOf('Widget build(BuildContext context)');
    final buildSource = source.substring(buildStart);

    final search = buildSource.indexOf('_buildClubFilterControls');
    final mine = buildSource.indexOf("title: '나의 모임'");
    final nearby = buildSource.indexOf('_buildNearbyClubsSection');
    final recruiting = buildSource.indexOf('TeamRecruitingBoard(');
    final recommended = buildSource.indexOf("'추천 모임'");

    expect(search, greaterThanOrEqualTo(0));
    expect(mine, greaterThan(search));
    expect(nearby, greaterThan(mine));
    expect(recruiting, greaterThan(nearby));
    expect(recommended, greaterThan(recruiting));
  });

  test('가입 모임과 모집글이 없으면 해당 섹션을 만들지 않는다', () {
    final source = File('lib/screens/clubs_screen.dart').readAsStringSync();

    expect(source, contains('if (joinedClubs.isNotEmpty)'));
    expect(source, contains('if (visibleRecruitingPosts.isNotEmpty)'));
  });
}
