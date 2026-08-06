import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('클럽 화면은 검색·나의 클럽·주변·모집·추천 순서로 구성된다', () {
    final source = File('lib/screens/clubs_screen.dart').readAsStringSync();
    final buildStart = source.indexOf('Widget build(BuildContext context)');
    final buildSource = source.substring(buildStart);

    final search = buildSource.indexOf('_buildClubFilterControls');
    final mine = buildSource.indexOf("title: '나의 클럽'");
    final nearby = buildSource.indexOf('_buildNearbyClubsSection');
    final recruiting = buildSource.indexOf('TeamRecruitingBoard(');
    final recommended = buildSource.indexOf("'추천 클럽'");

    expect(search, greaterThanOrEqualTo(0));
    expect(mine, greaterThan(search));
    expect(nearby, greaterThan(mine));
    expect(recruiting, greaterThan(nearby));
    expect(recommended, greaterThan(recruiting));
  });

  test('가입·승인대기 클럽이 없으면 나의 클럽 섹션을 만들지 않는다', () {
    final source = File('lib/screens/clubs_screen.dart').readAsStringSync();

    expect(
      source,
      contains('if (joinedClubs.isNotEmpty || pendingClubs.isNotEmpty)'),
    );
  });

  test('모집글 0건이어도 운영진은 첫 모집글을 쓸 수 있다', () {
    final source = File('lib/screens/clubs_screen.dart').readAsStringSync();

    expect(
      source,
      contains(
          'visibleRecruitingPosts.isNotEmpty ||\n                      managedClubs.isNotEmpty'),
    );
  });
}
