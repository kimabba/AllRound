import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'lib/screens/clubs/club_detail_screen.dart',
  ).readAsStringSync();

  test('게시판은 전체 없이 공지·자유·모집·사진·가입인사 순서다', () {
    final start = source.indexOf('class _PostsTabState');
    final end = source.indexOf('class _PostWriteEntry', start);
    final postsTab = source.substring(start, end);

    expect(postsTab, contains("String _activeTag = 'free';"));
    expect(postsTab, isNot(contains("label: '전체'")));

    final notice = postsTab.indexOf("label: '공지'");
    final free = postsTab.indexOf("label: '자유'");
    final recruit = postsTab.indexOf("label: '모집'");
    final photo = postsTab.indexOf("label: '사진'");
    final intro = postsTab.indexOf("label: '가입인사'");

    expect(notice, greaterThanOrEqualTo(0));
    expect(notice, lessThan(free));
    expect(free, lessThan(recruit));
    expect(recruit, lessThan(photo));
    expect(photo, lessThan(intro));
  });

  test('글쓰기 분류도 게시판과 같은 순서를 사용한다', () {
    final start = source.indexOf('class _PostCreateSheetState');
    final end = source.indexOf('class _PostTagChoice', start);
    final createSheet = source.substring(start, end);

    final notice = createSheet.indexOf("label: '공지'");
    final free = createSheet.indexOf("label: '자유'");
    final recruit = createSheet.indexOf("label: '모집'");
    final photo = createSheet.indexOf("label: '사진'");
    final intro = createSheet.indexOf("label: '가입인사'");

    expect(notice, greaterThanOrEqualTo(0));
    expect(notice, lessThan(free));
    expect(free, lessThan(recruit));
    expect(recruit, lessThan(photo));
    expect(photo, lessThan(intro));
  });
}
