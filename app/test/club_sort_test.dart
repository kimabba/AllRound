import 'package:allround/models/tournament.dart';
import 'package:allround/utils/club_sort.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Club club(
  String id,
  String name, {
  int memberCount = 0,
  DateTime? createdAt,
}) {
  return Club(
    id: id,
    sport: 'futsal',
    name: name,
    memberCount: memberCount,
    createdAt: createdAt,
  );
}

void main() {
  test('회원 많은 순은 동률일 때 이름순으로 정렬한다', () {
    final result = sortClubs(
      [
        club('1', '나클럽', memberCount: 10),
        club('2', '다클럽', memberCount: 3),
        club('3', '가클럽', memberCount: 10),
      ],
      ClubSortOrder.memberCount,
    );

    expect(result.map((item) => item.id), ['3', '1', '2']);
  });

  test('최근 등록순은 날짜 없는 클럽을 마지막에 둔다', () {
    final result = sortClubs(
      [
        club('1', '날짜없음'),
        club('2', '이전', createdAt: DateTime.utc(2026, 7, 1)),
        club('3', '최근', createdAt: DateTime.utc(2026, 7, 14)),
      ],
      ClubSortOrder.newest,
    );

    expect(result.map((item) => item.id), ['3', '2', '1']);
  });

  test('정렬 선택값을 저장하고 복원한다', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    expect(await loadClubSortOrder(), ClubSortOrder.recommended);
    await saveClubSortOrder(ClubSortOrder.name);
    expect(await loadClubSortOrder(), ClubSortOrder.name);
  });
}
