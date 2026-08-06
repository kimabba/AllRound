import { canListClubMembers } from '../clubs-join/member_visibility.ts';

function assertEquals(actual: boolean, expected: boolean): void {
  if (actual !== expected) {
    throw new Error(`expected ${expected}, received ${actual}`);
  }
}

Deno.test('approved 클럽의 멤버 목록은 가입 전에도 공개된다', () => {
  assertEquals(
    canListClubMembers({
      isActiveMember: false,
      isAdmin: false,
      clubStatus: 'approved',
    }),
    true,
  );
});

Deno.test('승인 전·반려 클럽의 멤버 목록은 비회원에게 공개되지 않는다', () => {
  for (const clubStatus of ['pending', 'rejected', null]) {
    assertEquals(
      canListClubMembers({
        isActiveMember: false,
        isAdmin: false,
        clubStatus,
      }),
      false,
    );
  }
});

Deno.test('활성 멤버와 관리자는 클럽 상태와 관계없이 멤버 목록을 볼 수 있다', () => {
  assertEquals(
    canListClubMembers({
      isActiveMember: true,
      isAdmin: false,
      clubStatus: 'pending',
    }),
    true,
  );
  assertEquals(
    canListClubMembers({
      isActiveMember: false,
      isAdmin: true,
      clubStatus: 'rejected',
    }),
    true,
  );
});

Deno.test('해당 클럽에서 차단된 비회원은 승인된 클럽 멤버 목록도 볼 수 없다', () => {
  assertEquals(
    canListClubMembers({
      isActiveMember: false,
      isAdmin: false,
      clubStatus: 'approved',
      isBanned: true,
    }),
    false,
  );
});
