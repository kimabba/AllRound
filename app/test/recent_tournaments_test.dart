import 'package:allround/models/tournament.dart';
import 'package:allround/utils/recent_tournaments.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Tournament tournament(String id, {String? title}) {
  return Tournament(
    id: id,
    sport: 'tennis',
    title: title ?? '대회 $id',
    startDate: DateTime.utc(2026, 8, 1),
    applicationDeadline: DateTime.utc(2026, 7, 25),
    region: '광주',
    eligibleGrades: const ['div3'],
    status: 'published',
  );
}

void main() {
  late RecentTournamentStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = RecentTournamentStore(await SharedPreferences.getInstance());
  });

  test('최근 본 대회를 최신순으로 저장하고 같은 대회는 중복 제거한다', () async {
    await store.record(
      'user-1',
      tournament('one', title: '처음 제목'),
      viewedAt: DateTime.utc(2026, 7, 14, 1),
    );
    await store.record(
      'user-1',
      tournament('two'),
      viewedAt: DateTime.utc(2026, 7, 14, 2),
    );
    await store.record(
      'user-1',
      tournament('one', title: '수정된 제목'),
      viewedAt: DateTime.utc(2026, 7, 14, 3),
    );

    final entries = store.load('user-1');
    expect(entries.map((entry) => entry.id), ['one', 'two']);
    expect(entries.first.title, '수정된 제목');
    expect(entries.first.viewedAt, DateTime.utc(2026, 7, 14, 3));
  });

  test('사용자별로 분리하고 최대 10개만 보관한다', () async {
    for (var index = 0; index < 12; index++) {
      await store.record('user-1', tournament('$index'));
    }
    await store.record('user-2', tournament('other'));

    expect(store.load('user-1'), hasLength(10));
    expect(store.load('user-1').first.id, '11');
    expect(store.load('user-2').single.id, 'other');
  });

  test('손상된 저장값은 빈 목록으로 안전하게 처리한다', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'tournaments.recent.v1.user-1': 'not-json',
    });
    final malformedStore =
        RecentTournamentStore(await SharedPreferences.getInstance());

    expect(malformedStore.load('user-1'), isEmpty);
  });
}
