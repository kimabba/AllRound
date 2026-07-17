import 'package:flutter_test/flutter_test.dart';
import 'package:allround/models/tournament.dart';
import 'package:allround/utils/profile_clubs.dart';

void main() {
  test('관리 중인 클럽과 가입한 클럽을 나눈다', () {
    final groups = groupProfileClubs([
      _club(id: 'owner', role: 'owner', status: 'pending'),
      _club(id: 'manager', role: 'manager'),
      _club(id: 'member', role: 'member'),
      _club(id: 'not-approved', role: 'member', status: 'pending'),
      _club(id: 'none'),
    ]);

    expect(groups.managed.map((club) => club.id), ['owner']);
    expect(groups.joined.map((club) => club.id), ['manager', 'member']);
  });
}

Club _club({
  required String id,
  String? role,
  String status = 'approved',
}) {
  return Club(
    id: id,
    sport: 'tennis',
    name: id,
    myRole: role,
    status: status,
  );
}
