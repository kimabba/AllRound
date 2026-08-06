import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('검색 결과는 검색창 바로 아래, 기본 추천은 기존 섹션 뒤에 둔다', () {
    final source = File('lib/screens/clubs_screen.dart').readAsStringSync();
    final buildStart = source.indexOf('Widget build(BuildContext context)');
    final buildSource = source.substring(buildStart);

    final search = buildSource.indexOf('_buildClubFilterControls');
    final searchResults = buildSource.indexOf(
      '_buildClubDiscoveryResults(',
      search,
    );
    final mine = buildSource.indexOf("title: '나의 클럽'");
    final nearby = buildSource.indexOf('_buildNearbyClubsSection');
    final recruiting = buildSource.indexOf('TeamRecruitingBoard(');
    final recommended = buildSource.indexOf(
      '_buildClubDiscoveryResults(',
      searchResults + 1,
    );

    expect(search, greaterThanOrEqualTo(0));
    expect(searchResults, greaterThan(search));
    expect(mine, greaterThan(searchResults));
    expect(nearby, greaterThan(mine));
    expect(recruiting, greaterThan(nearby));
    expect(recommended, greaterThan(recruiting));
  });

  test('클럽 이름을 입력하는 즉시 검색어를 반영한다', () {
    final source = File('lib/screens/clubs_screen.dart').readAsStringSync();

    expect(
      source,
      contains('onChanged: (value) {\n'
          '            setState(() => _clubNameQuery = value.trim());'),
    );
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
