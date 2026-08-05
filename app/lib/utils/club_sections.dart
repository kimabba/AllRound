import '../models/tournament.dart';

/// "나의 모임" 섹션에서 승인 대기 카드로 보여줄 목록 (JY-150).
///
/// 두 종류의 대기가 한 섹션에 섞인다:
///   1) 내가 만들었지만 관리자 승인 전인 모임 (`clubs.status='pending'`)
///   2) 내가 낸 가입 신청이 대기 중인 모임 (`club_join_requests`)
///
/// 1번이 어디에도 안 보여서 사용자가 제출 여부를 확인하지 못하고 같은 모임을 다시
/// 만드는 문제가 있었다. 반려된 모임(`isRejected`)은 양쪽 모두에서 제외한다 — 2번은
/// 신청 자체는 대기 중이어도 모임이 나중에 반려될 수 있어(관리자가 승인된 모임을
/// 반려로 되돌리는 경우) 명시적으로 걸러야 한다.
List<Club> pendingClubCards({
  required List<Club> myClubs,
  required List<Club> joinRequestClubs,
}) {
  final createdPending = myClubs.where((club) => club.isPending).toList();
  final approvedIds = myClubs.where((club) => club.isApproved).map((c) => c.id);
  return [
    ...createdPending,
    // 반려됐거나, 이미 멤버로 참여 중이거나, 위에 넣은 모임은 뺀다.
    ...joinRequestClubs.where(
      (club) =>
          !club.isRejected &&
          !approvedIds.contains(club.id) &&
          !createdPending.any((pending) => pending.id == club.id),
    ),
  ];
}
