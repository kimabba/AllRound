import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('클럽 헤더는 공통 종목 선택기를 쓰고 본문의 옛 주종목 선택기를 제거한다', () {
    final source = File('lib/screens/clubs_screen.dart').readAsStringSync();

    expect(source, contains('title: const SportTitle()'));
    expect(source, isNot(contains("title: const Text('클럽')")));
    expect(source, isNot(contains('내 주종목')));
    expect(source, isNot(contains('class _ClubSportSelector')));
  });

  test('검색 결과는 검색창 바로 아래, 기본 추천은 기존 섹션 뒤에 둔다', () {
    final source = File('lib/screens/clubs_screen.dart').readAsStringSync();
    final buildStart = source.indexOf('Widget build(BuildContext context)');
    final buildSource = source.substring(buildStart);

    final search = buildSource.indexOf('_buildClubFilterControls');
    final searchResults = buildSource.indexOf(
      '_buildClubDiscoveryResults(',
      search,
    );
    final mine = buildSource.indexOf('_MyClubsCarousel(');
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
      contains(
        'onChanged: (value) {\n'
        '            setState(() => _clubNameQuery = value.trim());',
      ),
    );
  });

  test('클럽 검색은 스크롤과 버튼으로 키보드를 닫는다', () {
    final source = File('lib/screens/clubs_screen.dart').readAsStringSync();

    expect(
      source,
      contains(
        'keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag',
      ),
    );
    expect(source, contains("tooltip: '키보드 닫기'"));
    expect(
      source,
      contains('onTapOutside: (_) => _clubNameQueryFocusNode.unfocus()'),
    );
  });

  test('나의 클럽 배너는 카드 높이를 먼저 확보해 다음 내용과 겹치지 않는다', () {
    final source = File('lib/screens/clubs_screen.dart').readAsStringSync();
    final carousel = source.indexOf('class _MyClubsCarouselState');
    final banner = source.indexOf(
      'SizedBox(\n          height: 108,',
      carousel,
    );
    final layout = source.indexOf('child: LayoutBuilder(', banner);
    final pageView = source.indexOf('child: PageView.builder(', layout);

    expect(carousel, greaterThanOrEqualTo(0));
    expect(banner, greaterThan(carousel));
    expect(layout, greaterThan(banner));
    expect(pageView, greaterThan(layout));
  });

  test('가입·승인대기 클럽이 없으면 나의 클럽 섹션을 만들지 않는다', () {
    final source = File('lib/screens/clubs_screen.dart').readAsStringSync();

    expect(
      source,
      contains('if (joinedClubs.isNotEmpty || pendingClubs.isNotEmpty)'),
    );
  });

  test('디자인 프리뷰는 테니스와 풋살 클럽을 각각 10개 제공한다', () {
    final source = File('lib/screens/clubs_screen.dart').readAsStringSync();
    final tennisIds = RegExp(
      "id: 'preview-tennis-\\d{2}'",
    ).allMatches(source).map((match) => match.group(0)).toSet();
    final futsalIds = RegExp(
      "id: 'preview-futsal-\\d{2}'",
    ).allMatches(source).map((match) => match.group(0)).toSet();

    expect(tennisIds, hasLength(10));
    expect(futsalIds, hasLength(10));
    expect(source, contains(_tennisLogoAssetContract));
    expect(source, contains(_futsalLogoAssetContract));
  });

  test('모집글 0건이어도 운영진은 첫 모집글을 쓸 수 있다', () {
    final source = File('lib/screens/clubs_screen.dart').readAsStringSync();

    expect(
      source,
      contains(
        'visibleRecruitingPosts.isNotEmpty ||\n                      managedClubs.isNotEmpty',
      ),
    );
  });

  test('클럽 홈은 세 가로 목록을 최대 5개로 제한하고 하단 전체보기만 둔다', () {
    final screen = File('lib/screens/clubs_screen.dart').readAsStringSync();
    final recruiting = File(
      'lib/widgets/clubs/team_recruiting_widgets.dart',
    ).readAsStringSync();

    expect(screen, contains('recommendedClubs.take(5).toList()'));
    expect(screen, contains('itemCount: nearby.take(5).length'));
    expect(recruiting, contains('itemCount: posts.take(5).length'));
    expect(screen, isNot(contains('trailingLabel:')));
    expect(recruiting, isNot(contains('onViewAll')));
    expect(
      RegExp("label: const Text\\('전체보기'\\)").allMatches(screen).length,
      1,
    );
  });

  test('클럽과 팀원 모집 홈 카드는 좁은 폭으로 다음 카드를 예고한다', () {
    final screen = File('lib/screens/clubs_screen.dart').readAsStringSync();
    final recruiting = File(
      'lib/widgets/clubs/team_recruiting_widgets.dart',
    ).readAsStringSync();

    expect(screen, contains('width: 156'));
    expect(recruiting, contains('width: 156'));
  });
}

const _tennisLogoAssetContract =
    "const _tennisLogoAsset = 'asset://assets/images/clubs/tennis-logo.png'";
const _futsalLogoAssetContract =
    "const _futsalLogoAsset = 'asset://assets/images/clubs/futsal-logo.png'";
