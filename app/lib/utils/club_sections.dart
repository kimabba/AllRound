import '../models/tournament.dart';

/// "나의 클럽" 섹션에서 승인 대기 카드로 보여줄 목록 (JY-150).
///
/// 두 종류의 대기가 한 섹션에 섞인다:
///   1) 내가 만들었지만 관리자 승인 전인 클럽 (`clubs.status='pending'`)
///   2) 내가 낸 가입 신청이 대기 중인 클럽 (`club_join_requests`)
///
/// 1번이 어디에도 안 보여서 사용자가 제출 여부를 확인하지 못하고 같은 클럽을 다시
/// 만드는 문제가 있었다. 반려된 클럽(`isRejected`)은 어느 쪽에도 들어가지 않는다.
List<Club> pendingClubCards({
  required List<Club> myClubs,
  required List<Club> joinRequestClubs,
}) {
  final createdPending = myClubs.where((club) => club.isPending).toList();
  final approvedIds = myClubs.where((club) => club.isApproved).map((c) => c.id);
  return [
    ...createdPending,
    // 이미 멤버로 참여 중이거나 위에 넣은 클럽은 중복이라 뺀다.
    ...joinRequestClubs.where(
      (club) =>
          !approvedIds.contains(club.id) &&
          !createdPending.any((pending) => pending.id == club.id),
    ),
  ];
}
