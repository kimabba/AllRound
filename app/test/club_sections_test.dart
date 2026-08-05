import 'package:flutter_test/flutter_test.dart';

import 'package:allround/models/tournament.dart';
import 'package:allround/utils/club_sections.dart';

Club club(String id, {required String status, String? role}) => Club(
      id: id,
      sport: 'tennis',
      name: '모임 $id',
      status: status,
      myRole: role,
    );

void main() {
  test('내가 만든 승인 대기 모임이 대기 카드에 뜬다 (JY-150)', () {
    final cards = pendingClubCards(
      myClubs: [club('mine', status: 'pending', role: 'owner')],
      joinRequestClubs: const [],
    );

    expect(cards.map((c) => c.id), ['mine']);
  });

  test('승인된 모임은 대기 카드가 아니라 참여 중으로 남는다', () {
    final cards = pendingClubCards(
      myClubs: [club('approved', status: 'approved', role: 'owner')],
      joinRequestClubs: const [],
    );

    expect(cards, isEmpty);
  });

  test('반려된 모임은 내가 만든 것이든 가입신청한 것이든 노출하지 않는다', () {
    expect(
      pendingClubCards(
        myClubs: [club('mine-rejected', status: 'rejected', role: 'owner')],
        joinRequestClubs: const [],
      ),
      isEmpty,
    );

    // 승인된 모임에 가입 신청한 뒤 관리자가 그 모임을 반려로 되돌리면,
    // 신청은 아직 pending 이지만 모임은 rejected 로 내려온다.
    expect(
      pendingClubCards(
        myClubs: const [],
        joinRequestClubs: [club('requested-rejected', status: 'rejected')],
      ),
      isEmpty,
    );
  });

  test('가입신청 대기는 그대로 유지되고, 이미 참여 중인 모임은 빠진다', () {
    final cards = pendingClubCards(
      myClubs: [club('joined', status: 'approved', role: 'member')],
      joinRequestClubs: [
        club('joined', status: 'approved'),
        club('requested', status: 'approved'),
      ],
    );

    expect(cards.map((c) => c.id), ['requested']);
  });

  test('같은 모임이 생성 대기와 가입신청 양쪽에 있어도 한 번만 뜬다', () {
    final cards = pendingClubCards(
      myClubs: [club('dup', status: 'pending', role: 'owner')],
      joinRequestClubs: [club('dup', status: 'pending')],
    );

    expect(cards.map((c) => c.id), ['dup']);
  });
}
