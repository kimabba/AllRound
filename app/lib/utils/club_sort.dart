import 'package:shared_preferences/shared_preferences.dart';

import '../models/tournament.dart';

const _clubSortPreferenceKey = 'clubs.sort_order.v1';

enum ClubSortOrder {
  recommended('recommended', '추천순'),
  memberCount('member_count', '회원 많은 순'),
  newest('newest', '최근 등록순'),
  name('name', '이름순');

  const ClubSortOrder(this.code, this.label);

  final String code;
  final String label;

  static ClubSortOrder fromCode(String? code) {
    return ClubSortOrder.values.firstWhere(
      (value) => value.code == code,
      orElse: () => ClubSortOrder.recommended,
    );
  }
}

Future<ClubSortOrder> loadClubSortOrder() async {
  final preferences = await SharedPreferences.getInstance();
  return ClubSortOrder.fromCode(
    preferences.getString(_clubSortPreferenceKey),
  );
}

Future<void> saveClubSortOrder(ClubSortOrder order) async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.setString(_clubSortPreferenceKey, order.code);
}

List<Club> sortClubs(List<Club> source, ClubSortOrder order) {
  final sorted = List<Club>.of(source);
  switch (order) {
    case ClubSortOrder.recommended:
      return sorted;
    case ClubSortOrder.memberCount:
      sorted.sort((a, b) {
        final byMembers = b.memberCount.compareTo(a.memberCount);
        return byMembers != 0 ? byMembers : a.name.compareTo(b.name);
      });
    case ClubSortOrder.newest:
      sorted.sort((a, b) {
        final aDate = a.createdAt;
        final bDate = b.createdAt;
        if (aDate == null && bDate == null) return a.name.compareTo(b.name);
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        final byDate = bDate.compareTo(aDate);
        return byDate != 0 ? byDate : a.name.compareTo(b.name);
      });
    case ClubSortOrder.name:
      sorted.sort((a, b) => a.name.compareTo(b.name));
  }
  return sorted;
}
