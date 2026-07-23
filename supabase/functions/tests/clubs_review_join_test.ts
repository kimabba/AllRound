import { assertEquals } from 'std/assert/mod.ts';

import { canReviewClub, reviewJoin } from '../clubs-review-join/review.ts';

// ── 인메모리 Supabase 클라이언트 대역 ──────────────────────────────
// review.ts 가 실제로 호출하는 체인(select/eq/single/maybeSingle/upsert/
// update/insert + await)만 지원한다. `failOn` 으로 특정 테이블의 특정
// 연산을 실패시켜 "멤버 upsert 실패 시 신청은 pending 유지" 같은 경로를 재현한다.

type Row = Record<string, unknown>;
type Terminal = { data?: unknown; error: { message: string } | null };

class FakeDb {
  tables: Record<string, Row[]>;
  failOn: Set<string>;

  constructor(tables: Record<string, Row[]>, failOn: string[] = []) {
    this.tables = tables;
    this.failOn = new Set(failOn);
  }

  from(table: string): FakeBuilder {
    if (!this.tables[table]) this.tables[table] = [];
    return new FakeBuilder(this, table);
  }
}

class FakeBuilder {
  private op = 'select';
  private cols = '';
  private filters: Array<[string, unknown]> = [];
  private payload: Row | null = null;
  private conflict: string | null = null;

  constructor(private db: FakeDb, private table: string) {}

  select(cols: string): this {
    this.op = 'select';
    this.cols = cols;
    return this;
  }
  eq(col: string, val: unknown): this {
    this.filters.push([col, val]);
    return this;
  }
  upsert(row: Row, opts?: { onConflict?: string }): this {
    this.op = 'upsert';
    this.payload = row;
    this.conflict = opts?.onConflict ?? null;
    return this;
  }
  update(patch: Row): this {
    this.op = 'update';
    this.payload = patch;
    return this;
  }
  insert(row: Row): this {
    this.op = 'insert';
    this.payload = row;
    return this;
  }

  maybeSingle(): Promise<Terminal> {
    const err = this.failure();
    if (err) return Promise.resolve({ data: null, error: err });
    const rows = this.rows();
    return Promise.resolve({ data: rows.length ? this.mapRow(rows[0]) : null, error: null });
  }
  single(): Promise<Terminal> {
    const err = this.failure();
    if (err) return Promise.resolve({ data: null, error: err });
    const rows = this.rows();
    if (rows.length === 1) return Promise.resolve({ data: this.mapRow(rows[0]), error: null });
    return Promise.resolve({ data: null, error: { message: 'PGRST116: row not found' } });
  }

  then<R>(onF: (v: Terminal) => R, onR?: (reason: unknown) => R): Promise<R> {
    return Promise.resolve(this.resolveTerminal()).then(onF, onR);
  }

  private rows(): Row[] {
    return (this.db.tables[this.table] ?? []).filter((row) =>
      this.filters.every(([col, val]) => row[col] === val)
    );
  }
  private failure(): { message: string } | null {
    return this.db.failOn.has(`${this.table}.${this.op}`)
      ? { message: `${this.table}.${this.op} failed` }
      : null;
  }
  private mapRow(row: Row): Row {
    if (this.cols.includes('clubs(name)')) {
      const club = (this.db.tables.clubs ?? []).find((c) => c.id === row.club_id);
      return { ...row, clubs: club ? { name: club.name } : null };
    }
    return row;
  }
  private resolveTerminal(): Terminal {
    const err = this.failure();
    if (err) return this.op === 'select' ? { data: null, error: err } : { error: err };
    if (this.op === 'select') {
      return { data: this.rows().map((row) => this.mapRow(row)), error: null };
    }
    if (this.op === 'insert') {
      this.db.tables[this.table].push({ ...(this.payload ?? {}) });
      return { error: null };
    }
    if (this.op === 'upsert') {
      const keys = (this.conflict ?? 'id').split(',').map((k) => k.trim());
      const payload = this.payload ?? {};
      const idx = this.db.tables[this.table].findIndex((row) =>
        keys.every((k) => row[k] === payload[k])
      );
      if (idx >= 0) {
        this.db.tables[this.table][idx] = { ...this.db.tables[this.table][idx], ...payload };
      } else {
        this.db.tables[this.table].push({ ...payload });
      }
      return { error: null };
    }
    // update
    for (const row of this.rows()) Object.assign(row, this.payload);
    return { error: null };
  }
}

// review.ts 시그니처의 클라이언트 타입으로 캐스팅 (any 미사용)
function asClient(db: FakeDb): Parameters<typeof reviewJoin>[0] {
  return db as unknown as Parameters<typeof reviewJoin>[0];
}

function baseTables(): Record<string, Row[]> {
  return {
    clubs: [{ id: 'club-1', name: '테니스 크루' }],
    users: [
      { id: 'owner-1', role: 'user' },
      { id: 'manager-1', role: 'user' },
      { id: 'member-1', role: 'user' },
      { id: 'admin-1', role: 'admin' },
      { id: 'nobody-1', role: 'user' },
      { id: 'req-user', role: 'user' },
    ],
    club_members: [
      { club_id: 'club-1', user_id: 'owner-1', role: 'owner', status: 'active' },
      { club_id: 'club-1', user_id: 'manager-1', role: 'manager', status: 'active' },
      { club_id: 'club-1', user_id: 'member-1', role: 'member', status: 'active' },
      { club_id: 'club-1', user_id: 'inactive-owner', role: 'owner', status: 'pending' },
    ],
    club_join_requests: [
      { id: 'req-1', club_id: 'club-1', user_id: 'req-user', status: 'pending' },
    ],
    device_tokens: [],
    notifications: [],
  };
}

// ── canReviewClub: 권한 매트릭스 ──────────────────────────────────

Deno.test('canReviewClub: active owner/manager 는 허용, 일반 멤버는 거부', async () => {
  const db = new FakeDb(baseTables());
  assertEquals(await canReviewClub(asClient(db), 'owner-1', 'club-1'), true);
  assertEquals(await canReviewClub(asClient(db), 'manager-1', 'club-1'), true);
  assertEquals(await canReviewClub(asClient(db), 'member-1', 'club-1'), false);
});

Deno.test('canReviewClub: admin 은 멤버가 아니어도 허용', async () => {
  const db = new FakeDb(baseTables());
  assertEquals(await canReviewClub(asClient(db), 'admin-1', 'club-1'), true);
});

Deno.test('canReviewClub: 비멤버는 거부', async () => {
  const db = new FakeDb(baseTables());
  assertEquals(await canReviewClub(asClient(db), 'nobody-1', 'club-1'), false);
});

Deno.test('canReviewClub: status 가 active 가 아닌 owner 는 거부', async () => {
  const db = new FakeDb(baseTables());
  assertEquals(await canReviewClub(asClient(db), 'inactive-owner', 'club-1'), false);
});

// ── reviewJoin: 승인/거절 플로우 ──────────────────────────────────

Deno.test('reviewJoin: manager 승인 시 멤버 추가·상태 approved·알림 생성', async () => {
  const db = new FakeDb(baseTables());
  const result = await reviewJoin(asClient(db), {
    requestId: 'req-1',
    action: 'approve',
    reviewerId: 'manager-1',
  });

  assertEquals(result, { ok: true, action: 'approve' });

  const added = db.tables.club_members.find((m) => m.user_id === 'req-user');
  assertEquals(added?.role, 'member');
  assertEquals(added?.status, 'active');

  const request = db.tables.club_join_requests[0];
  assertEquals(request.status, 'approved');
  assertEquals(request.reviewed_by, 'manager-1');

  assertEquals(db.tables.notifications.length, 1);
  const notification = db.tables.notifications[0];
  assertEquals(notification.type, 'club_join_approved');
  assertEquals(notification.title, '클럽 가입이 승인되었습니다');
  assertEquals(notification.reference_type, 'club_join_request');
  assertEquals(notification.reference_id, 'req-1');
  assertEquals(notification.club_id, 'club-1');
  assertEquals(String(notification.body).includes('테니스 크루'), true);
});

Deno.test('reviewJoin: 탈퇴 후 재신청 승인 시 기존 멤버십을 active 로 복구', async () => {
  const tables = baseTables();
  tables.club_members.push({
    club_id: 'club-1',
    user_id: 'req-user',
    role: 'member',
    status: 'left',
    left_at: '2026-07-22T00:00:00.000Z',
  });
  const db = new FakeDb(tables);

  const result = await reviewJoin(asClient(db), {
    requestId: 'req-1',
    action: 'approve',
    reviewerId: 'owner-1',
  });

  assertEquals(result, { ok: true, action: 'approve' });
  const membership = db.tables.club_members.find((row) =>
    row.club_id === 'club-1' && row.user_id === 'req-user'
  );
  assertEquals(membership?.status, 'active');
  assertEquals(membership?.role, 'member');
  assertEquals(membership?.left_at, null);
});

Deno.test('reviewJoin: admin 거절 시 멤버 추가 없이 상태 rejected·거절 알림', async () => {
  const db = new FakeDb(baseTables());
  const result = await reviewJoin(asClient(db), {
    requestId: 'req-1',
    action: 'reject',
    reviewerId: 'admin-1',
  });

  assertEquals(result, { ok: true, action: 'reject' });
  assertEquals(db.tables.club_members.some((m) => m.user_id === 'req-user'), false);
  assertEquals(db.tables.club_join_requests[0].status, 'rejected');
  assertEquals(db.tables.notifications[0].type, 'club_join_rejected');
});

Deno.test('reviewJoin: 일반 멤버는 403 으로 거부', async () => {
  const db = new FakeDb(baseTables());
  const result = await reviewJoin(asClient(db), {
    requestId: 'req-1',
    action: 'approve',
    reviewerId: 'member-1',
  });

  assertEquals(result, {
    ok: false,
    status: 403,
    message: 'Forbidden: owner/manager or admin only',
  });
  // 권한 없으면 아무 것도 바꾸지 않는다
  assertEquals(db.tables.club_join_requests[0].status, 'pending');
  assertEquals(db.tables.notifications.length, 0);
});

Deno.test('reviewJoin: 멤버 upsert 실패 시 신청은 pending 유지(교착 방지 불변식)', async () => {
  const db = new FakeDb(baseTables(), ['club_members.upsert']);
  const result = await reviewJoin(asClient(db), {
    requestId: 'req-1',
    action: 'approve',
    reviewerId: 'owner-1',
  });

  assertEquals(result.ok, false);
  assertEquals((result as { status: number }).status, 500);
  // 상태를 approved 로 바꾸기 전에 멈춰야 재시도가 가능하다
  assertEquals(db.tables.club_join_requests[0].status, 'pending');
  assertEquals(db.tables.club_members.some((m) => m.user_id === 'req-user'), false);
  assertEquals(db.tables.notifications.length, 0);
});

Deno.test('reviewJoin: 상태 update 실패 시 500·알림 미생성', async () => {
  const db = new FakeDb(baseTables(), ['club_join_requests.update']);
  const result = await reviewJoin(asClient(db), {
    requestId: 'req-1',
    action: 'approve',
    reviewerId: 'owner-1',
  });

  assertEquals(result.ok, false);
  assertEquals((result as { status: number }).status, 500);
  // update 실패는 upsert 뒤 단계 — 알림까지 가면 안 된다
  assertEquals(db.tables.notifications.length, 0);
});

Deno.test('reviewJoin: 존재하지 않는 신청은 404', async () => {
  const db = new FakeDb(baseTables());
  const result = await reviewJoin(asClient(db), {
    requestId: 'missing',
    action: 'approve',
    reviewerId: 'owner-1',
  });

  assertEquals(result, { ok: false, status: 404, message: 'Join request not found' });
});

Deno.test('reviewJoin: 이미 처리된 신청은 409', async () => {
  const tables = baseTables();
  tables.club_join_requests[0].status = 'approved';
  const db = new FakeDb(tables);
  const result = await reviewJoin(asClient(db), {
    requestId: 'req-1',
    action: 'approve',
    reviewerId: 'owner-1',
  });

  assertEquals(result, { ok: false, status: 409, message: 'Already reviewed' });
  // 이미 처리된 신청은 멤버 추가·알림 등 어떤 부작용도 없어야 한다
  assertEquals(db.tables.club_members.some((m) => m.user_id === 'req-user'), false);
  assertEquals(db.tables.notifications.length, 0);
});

Deno.test('reviewJoin: 클럽 정보가 없으면 알림 본문은 기본 "클럽" 표기', async () => {
  const tables = baseTables();
  tables.clubs = []; // clubs(name) 조인이 비면 fallback
  const db = new FakeDb(tables);
  const result = await reviewJoin(asClient(db), {
    requestId: 'req-1',
    action: 'approve',
    reviewerId: 'owner-1',
  });

  assertEquals(result.ok, true);
  assertEquals(String(db.tables.notifications[0].body).startsWith('클럽 가입이 승인'), true);
});
