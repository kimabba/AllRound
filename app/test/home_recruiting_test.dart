import 'package:allround/models/club_recruiting.dart';
import 'package:flutter_test/flutter_test.dart';

RecruitingPostPreview post(
  String id, {
  String sport = 'tennis',
  bool closed = false,
  required DateTime createdAt,
}) {
  return RecruitingPostPreview(
    id: id,
    clubId: 'c-$id',
    sport: sport,
    clubName: 'club',
    title: 't-$id',
    region: '광주',
    position: null,
    place: 'place',
    schedule: 'sch',
    grade: 'g',
    gender: 'a',
    age: 'a',
    fieldCount: 0,
    keeperCount: 0,
    totalCount: 1,
    cost: '협의',
    isClosed: closed,
    createdAt: createdAt,
  );
}

void main() {
  final t0 = DateTime(2026, 7, 1);

  test('pickHomeRecruiting: 풋살 우선 → 그다음 최신순, 마감글 제외', () {
    final result = pickHomeRecruiting([
      post('tennis-old', createdAt: t0),
      post('tennis-new', createdAt: t0.add(const Duration(days: 5))),
      post('futsal-old', sport: 'futsal', createdAt: t0),
      post('futsal-new', sport: 'futsal', createdAt: t0.add(const Duration(days: 2))),
      post('closed-futsal', sport: 'futsal', closed: true, createdAt: t0.add(const Duration(days: 9))),
    ]);
    // 풋살 먼저(최신순), 그다음 테니스(최신순). 마감글은 빠짐.
    expect(result.map((p) => p.id).toList(),
        ['futsal-new', 'futsal-old', 'tennis-new', 'tennis-old']);
  });

  test('pickHomeRecruiting: limit 적용', () {
    final posts =
        List.generate(6, (i) => post('p$i', createdAt: t0.add(Duration(days: i))));
    expect(pickHomeRecruiting(posts, limit: 4).length, 4);
  });
}
