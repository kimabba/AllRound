const deletedByOwnerReason = 'deleted_by_owner';

/**
 * 소프트 삭제된 클럽은 생성자 조건에 계속 걸리므로 "내 클럽" 응답에서 제외한다.
 * DB 행은 감사·연관 데이터 보존을 위해 남겨두되 사용자 목록에는 다시 노출하지 않는다.
 */
export function visibleMyClubRows(
  rows: readonly Record<string, unknown>[],
): Record<string, unknown>[] {
  return rows.filter((row) => row['status_reason'] !== deletedByOwnerReason);
}
