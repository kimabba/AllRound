// 페르소나 시뮬레이션 기계부 CLI (로컬 스택 대상)
// 사용: deno run -A sim.ts journey '<persona-json>'
//       deno run -A sim.ts chat <token> "<message>"
// 페르소나 브레인(Haiku)이 subcommand 로 여정을 살 수 있게 각 단계를 노출.

const API = 'http://127.0.0.1:54321';
const ANON = Deno.env.get('ANON_KEY') ?? '';

interface StepLog {
  step: string;
  ok: boolean;
  status: number;
  detail: string;
}

async function signup(
  email: string,
  password: string,
  birthDate: string,
): Promise<{ token: string; uid: string; log: StepLog }> {
  const res = await fetch(`${API}/auth/v1/signup`, {
    method: 'POST',
    headers: { apikey: ANON, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, data: { birth_date: birthDate } }),
  });
  const body = await res.json().catch(() => ({}));
  const token = body.access_token ?? '';
  const uid = body.user?.id ?? body.id ?? '';
  return {
    token,
    uid,
    log: {
      step: 'signup',
      ok: res.ok && !!token,
      status: res.status,
      detail: res.ok ? `uid=${uid.slice(0, 8)}` : JSON.stringify(body).slice(0, 160),
    },
  };
}

function authHeaders(token: string) {
  return {
    apikey: ANON,
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
  };
}

// PostgREST 직접 쓰기(온보딩) — RLS: 본인 행
async function rest(
  token: string,
  path: string,
  method: string,
  body?: unknown,
): Promise<{ ok: boolean; status: number; data: unknown }> {
  const res = await fetch(`${API}/rest/v1/${path}`, {
    method,
    headers: { ...authHeaders(token), Prefer: 'return=representation' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await res.json().catch(() => null);
  return { ok: res.ok, status: res.status, data };
}

interface Persona {
  email: string;
  password: string;
  birth_date: string;
  name: string;
  nickname: string;
  sport: 'tennis' | 'futsal';
  grade: string;
  region_code?: string; // 테니스 협회 권역
  org?: string; // 테니스 협회
  division_codes?: string[];
  questions: string[]; // 채팅 질문(페르소나 성향 반영)
}

async function onboard(
  token: string,
  uid: string,
  p: Persona,
): Promise<StepLog[]> {
  const logs: StepLog[] = [];

  // 1) users 프로필 (이름/닉네임)
  const prof = await rest(token, `users?id=eq.${uid}`, 'PATCH', {
    name: p.name,
    nickname: p.nickname,
  });
  logs.push({
    step: 'onboard.profile',
    ok: prof.ok,
    status: prof.status,
    detail: prof.ok ? 'name/nickname set' : JSON.stringify(prof.data).slice(0, 140),
  });

  // 2) user_sports
  const us = await rest(token, 'user_sports', 'POST', {
    user_id: uid,
    sport: p.sport,
    grade: p.grade,
    is_primary: true,
  });
  logs.push({
    step: 'onboard.sport',
    ok: us.ok,
    status: us.status,
    detail: us.ok ? `${p.sport}/${p.grade}` : JSON.stringify(us.data).slice(0, 140),
  });

  // 3) 테니스면 협회 등록
  if (p.sport === 'tennis' && p.org) {
    const codes = p.division_codes ?? [];
    const to = await rest(token, 'user_tennis_orgs', 'POST', {
      user_id: uid,
      org: p.org,
      region_code: p.region_code,
      division_codes: codes,
      division: codes[0] ?? p.grade, // division(단수) NOT NULL
      is_primary: true,
    });
    logs.push({
      step: 'onboard.tennis_org',
      ok: to.ok,
      status: to.status,
      detail: to.ok ? `${p.org}/${p.region_code}` : JSON.stringify(to.data).slice(0, 140),
    });
  }
  return logs;
}

async function clubsSearch(token: string, sport: string): Promise<StepLog & { ids: string[] }> {
  const res = await fetch(`${API}/functions/v1/clubs-search?sport=${sport}&limit=10`, {
    headers: authHeaders(token),
  });
  const body = await res.json().catch(() => ({}));
  const clubs = body.clubs ?? body ?? [];
  const ids = Array.isArray(clubs) ? clubs.map((c: Record<string, unknown>) => c.id as string) : [];
  return {
    step: 'clubs.search',
    ok: res.ok,
    status: res.status,
    detail: res.ok ? `${ids.length} clubs` : JSON.stringify(body).slice(0, 140),
    ids,
  };
}

async function clubsJoin(token: string, clubId: string): Promise<StepLog> {
  const res = await fetch(`${API}/functions/v1/clubs-join`, {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify({ club_id: clubId, action: 'request' }),
  });
  const body = await res.json().catch(() => ({}));
  return {
    step: 'clubs.join',
    ok: res.ok,
    status: res.status,
    detail: res.ok ? 'join requested' : JSON.stringify(body).slice(0, 140),
  };
}

async function tournamentsSearch(
  token: string,
  sport: string,
  regionCode?: string,
): Promise<StepLog & { count: number }> {
  const qs = new URLSearchParams({ sport });
  if (regionCode) qs.set('region_code', regionCode);
  qs.set('only_my_grade', 'false');
  const res = await fetch(`${API}/functions/v1/tournaments-search?${qs}`, {
    headers: authHeaders(token),
  });
  const body = await res.json().catch(() => ({}));
  const list = body.tournaments ?? body ?? [];
  const count = Array.isArray(list) ? list.length : 0;
  return {
    step: 'tournaments.search',
    ok: res.ok,
    status: res.status,
    detail: res.ok ? `${count} tournaments` : JSON.stringify(body).slice(0, 140),
    count,
  };
}

// 채팅 SSE 파싱 → intent + 답변 텍스트 + 에러여부
async function chatOnce(
  token: string,
  message: string,
  activeSport?: string,
): Promise<{ intent: string; answer: string; error: boolean; status: number }> {
  const res = await fetch(`${API}/functions/v1/chat`, {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify({ message, active_sport: activeSport }),
  });
  if (!res.ok || !res.body) {
    return { intent: '', answer: '', error: true, status: res.status };
  }
  const text = await new Response(res.body).text();
  let intent = '';
  let answer = '';
  for (const block of text.split('\n\n')) {
    const ev = block.match(/^event: (\w+)/)?.[1];
    const dataLine = block.match(/\ndata: (.*)$/s)?.[1] ?? block.match(/data: (.*)$/s)?.[1];
    if (!ev || !dataLine) continue;
    try {
      const data = JSON.parse(dataLine);
      if (ev === 'intent') intent = data.intent ?? '';
      if (ev === 'delta' && typeof data.text === 'string') answer += data.text;
    } catch { /* skip */ }
  }
  const error = answer.includes('일시적인 시스템 오류');
  return { intent, answer: answer.trim(), error, status: res.status };
}

// Gemini 무료 티어 RPM(429·일시오류) 대비 재시도+백오프
async function chat(
  token: string,
  message: string,
  activeSport?: string,
): Promise<{ intent: string; answer: string; error: boolean; status: number }> {
  let last = { intent: '', answer: '', error: true, status: 0 };
  for (let attempt = 0; attempt < 4; attempt++) {
    if (attempt > 0) await new Promise((r) => setTimeout(r, 4000 * attempt));
    last = await chatOnce(token, message, activeSport);
    if (!last.error && last.status !== 429) return last;
  }
  return last;
}

// 가입~온보딩~약관~클럽~대회 (Gemini 무관, 결정적) → 토큰 확보
async function setupPersona(
  p: Persona,
): Promise<{ token: string; uid: string; steps: StepLog[] }> {
  const steps: StepLog[] = [];
  const su = await signup(p.email, p.password, p.birth_date);
  steps.push(su.log);
  if (!su.token) return { token: '', uid: '', steps };

  steps.push(...(await onboard(su.token, su.uid, p)));

  const terms = await rest(su.token, 'rpc/accept_current_ugc_terms', 'POST', {});
  steps.push({
    step: 'ugc.accept_terms',
    ok: terms.ok,
    status: terms.status,
    detail: terms.ok ? 'accepted' : JSON.stringify(terms.data).slice(0, 140),
  });

  const cs = await clubsSearch(su.token, p.sport);
  steps.push({ step: cs.step, ok: cs.ok, status: cs.status, detail: cs.detail });
  if (cs.ids.length > 0) steps.push(await clubsJoin(su.token, cs.ids[0]));

  const ts = await tournamentsSearch(su.token, p.sport, p.region_code);
  steps.push({ step: ts.step, ok: ts.ok, status: ts.status, detail: ts.detail });

  return { token: su.token, uid: su.uid, steps };
}

async function journey(p: Persona) {
  const s = await setupPersona(p);
  const chats: Array<{ q: string; intent: string; error: boolean; answer: string }> = [];
  if (s.token) {
    for (const q of p.questions) {
      const c = await chat(s.token, q, p.sport);
      chats.push({ q, intent: c.intent, error: c.error, answer: c.answer.slice(0, 400) });
      await new Promise((r) => setTimeout(r, 1500));
    }
  }
  console.log(JSON.stringify({ persona: p.nickname, sport: p.sport, steps: s.steps, chats }, null, 2));
}

// ── CLI ──
const [cmd, ...argv] = Deno.args;
if (cmd === 'journey') {
  await journey(JSON.parse(argv[0]) as Persona);
} else if (cmd === 'setup') {
  const s = await setupPersona(JSON.parse(argv[0]) as Persona);
  console.log(JSON.stringify(s));
} else if (cmd === 'chat') {
  const [token, message, sport] = argv;
  console.log(JSON.stringify(await chat(token, message, sport), null, 2));
} else {
  console.error('usage: sim.ts journey|setup <persona-json> | chat <token> <message> [sport]');
  Deno.exit(1);
}
