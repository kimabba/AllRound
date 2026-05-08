# 단순화 / 코드 품질 검토 보고서

생성: 2026-05-08
범위: Match-up MVP, `app/lib/**` 19파일 + `supabase/functions/**` 13함수 + `supabase/migrations/00{1..8}_*.sql` (총 약 4,950줄)


---

## 요약

- 총 finding: **14개** (SIMP-01 ~ SIMP-14)
- 추천 변경 라인 수: **약 −230줄, +60줄 (순 −170줄)**, 즉 약 3.4% 감소
- 가장 큰 단순화 기회 3가지:
  1. **3개 테니스 크롤러의 95% 중복** (gwangju/jeonnam/korea, 약 295줄 → 약 130줄)
  2. **enums.ts 의 미사용 helper 제거** (`canEnter`, `rankOf`, `TENNIS_RANK`, `FUTSAL_RANK`)
  3. **semantic-search 의 RpcResult 타입 곡예** (~25줄을 ~10줄로 단순화)

전반적으로 코드는 이미 단순하고 깔끔한 편이다. **`Simplicity First` 기준에서 보면 큰 위반은 없으나**, 추측성 추상화(rankOf), 미사용 helper, 그리고 크롤러 3개의 boilerplate 가 눈에 띄는 정도다. MVP 단계에서는 SIMP-01, 02, 03, 06 만 즉시 처리하고 나머지는 보류해도 무방하다.

---

## 발견 사항

### [SIMP-01] 3개 테니스 크롤러 95% 중복

- **위치**:
  - `supabase/functions/crawl-tennis-gwangju/index.ts` (106줄)
  - `supabase/functions/crawl-tennis-jeonnam/index.ts` (91줄)
  - `supabase/functions/crawl-tennis-korea/index.ts` (96줄)
- **현재 코드** (3 파일 공통 패턴):
  ```ts
  // 각 파일이 동일 구조 반복:
  // 1) fetchListing(LIST_URL) — selector 만 다름
  // 2) fetchDetail(url) — selector 와 region 처리만 다름
  // 3) Deno.serve — startAudit / loop / finishAudit / errorResponse 100% 동일
  ```
  3개 함수의 `Deno.serve` 핸들러는 한 글자도 다르지 않다 (78~106, 63~91, 68~96 라인 비교).
  `fetchDetail` 도 90% 일치 — selector 문자열과 region 처리만 차이가 난다.
- **문제**: 4번째 사이트가 추가될 때마다 100줄짜리 boilerplate 가 1개 더 늘어난다. selector 만 바꾸면 되는 것이 SoC 측면에서 명확함에도 함수 단위로 복제됨.
- **권장**: `_shared/crawler.ts` 에 `runCrawler(source, region, listSelector, detailSelectors, listUrl, sport)` 형태의 high-level 진입함수를 추가하고 각 index.ts 는 설정만 export. Before/After:

  Before (`crawl-tennis-jeonnam/index.ts` 63~91):
  ```ts
  Deno.serve(async (req) => {
    const pre = preflight(req);
    if (pre) return pre;
    const audit = await startAudit(SOURCE);
    try {
      const items = await fetchListing();
      const errors: string[] = [];
      for (const item of items.slice(0, 30)) {
        try {
          const t = await fetchDetail(item.url);
          if (t) await upsertTournament(audit, 'tennis', t);
        } catch (e) {
          errors.push(`${item.url}: ${(e as Error).message}`);
        }
      }
      await finishAudit(audit, errors.length === 0 ? 'success' : 'partial', errors.join('\n'));
      return jsonResponse({ source: SOURCE, fetched: audit.fetched, ... });
    } catch (e) {
      await finishAudit(audit, 'failed', (e as Error).message);
      return errorResponse((e as Error).message, 500);
    }
  });
  ```

  After:
  ```ts
  // _shared/crawler.ts
  export async function runTennisCrawler(opts: {
    source: string;
    listUrl: string;
    region?: string;
    listSelector?: string;     // default 'a[href*="wr_id"]'
    titleSelectors?: string;   // default 'h1, .bo_v_tit, .title'
    bodySelectors?: string;    // default '#bo_v_atc, .view_content, article'
    detectRegion?: boolean;    // korea 전용
  }): Promise<Response> { /* 위 boilerplate 한번만 */ }

  // crawl-tennis-jeonnam/index.ts (전체)
  import { runTennisCrawler } from '../_shared/crawler.ts';
  Deno.serve((req) => runTennisCrawler(req, {
    source: 'tennis-jeonnam',
    region: '전남',
    listUrl: Deno.env.get('CRAWL_TENNIS_JEONNAM_URL') ?? 'https://jntennis.or.kr/...',
  }));
  ```
- **영향**: 3개 함수 합계 293줄 → 약 130줄(헬퍼 +50, 각 index 10줄). **순 −160줄**. 새 사이트 추가 비용도 100줄 → 5줄로 감소.

---

### [SIMP-02] enums.ts 의 미사용 helper

- **위치**: `supabase/functions/_shared/enums.ts` 10~23, 47~49, 71~75
- **현재 코드**:
  ```ts
  const TENNIS_RANK: Record<TennisGrade, number> = { rookie: 0, div5: 1, ... };
  const FUTSAL_RANK: Record<FutsalGrade, number> = { beginner: 0, ... };
  export function canEnter(userGrade: string, eligibleGrades: string[]): boolean {
    return eligibleGrades.includes(userGrade);
  }
  export function rankOf(sport: Sport, grade: string): number | null { ... }
  ```
- **문제**: `grep -rn "rankOf\|canEnter" supabase app` 결과, 정의 외 0건의 호출. `TENNIS_RANK`/`FUTSAL_RANK` 도 `rankOf` 안에서만 쓰인다. **`canEnter` 본문은 한 줄짜리 wrapper** (`includes(userGrade)`) 인데 호출처도 없다. 등급 매칭은 RLS RPC `tournaments_for_user` 에서 SQL 로 처리하므로 TS helper 필요 없음.
- **권장**: 23줄 일괄 삭제. 사용자 가이드라인 §2 "추측성 추상화 금지" 직접 위반 사례.
  ```ts
  // After: enums.ts 약 30줄 (현재 75줄)
  export const TENNIS_GRADES = [...] as const;
  export const FUTSAL_GRADES = [...] as const;
  export function isValidGrade(...)
  export const GRADE_LABELS = {...};
  export const SPORT_LABELS = {...};
  ```
- **영향**: 75줄 → 30줄, **−45줄**. enums.ts 의 주석 41~46 (canEnter 의 5줄짜리 의도 주석)도 함께 제거.

---

### [SIMP-03] grade_labels.dart 의 sportFromString → enum 왕복

- **위치**: `app/lib/utils/grade_labels.dart` 23~33, 호출처 6곳
- **현재 코드**:
  ```dart
  Sport sportFromString(String s) => s == 'futsal' ? Sport.futsal : Sport.tennis;
  String sportToString(Sport s) => s == Sport.futsal ? 'futsal' : 'tennis';
  String sportLabel(Sport sport) => sportLabels[sport] ?? '';
  String sportLabelFromString(String s) => sportLabel(sportFromString(s));
  ```
  `sportLabelFromString` 은 `"tennis"` → enum → label 으로 두 단계 변환. DB·API는 항상 string `"tennis"`/`"futsal"` 만 사용하고, enum 은 `OnboardingScreen` 한 곳에서만 의미가 있음.
- **문제**: enum 이 진짜로 필요한 곳은 `Map<Sport, String?> _selected` (onboarding) 한 군데뿐인데, 타입 왕복용 helper 4개가 layer 를 만든다.
- **권장**: enum 은 onboarding 에 국한하고 외부에는 `Map<String, String>` 라벨만 노출.
  ```dart
  // After:
  const tennisGrades = ['rookie', ...];
  const futsalGrades = ['beginner', ...];
  const sportLabels = {'tennis': '테니스', 'futsal': '풋살'};
  String sportLabel(String s) => sportLabels[s] ?? s;
  String gradeLabel(String g) => gradeLabels[g] ?? g;
  List<String> gradesFor(String sport) => sport == 'futsal' ? futsalGrades : tennisGrades;
  ```
  `sportLabelFromString` 호출처 6곳을 `sportLabel` 로 일괄 변경.
- **영향**: 33줄 → 약 18줄 (**−15줄**), 호출처 가독성 향상 (`sportLabelFromString(c.sport)` → `sportLabel(c.sport)`).
- **회귀 리스크**: onboarding 의 `Sport` enum 만 grade_labels 가 아닌 onboarding 파일 내부 private enum 으로 옮기면 됨. 다른 화면은 string 기반이라 영향 없음.

---

### [SIMP-04] semantic-search 의 RpcResult 캐스팅 곡예

- **위치**: `supabase/functions/semantic-search/index.ts` 56~84
- **현재 코드**:
  ```ts
  type RpcResult = { data: unknown; error: { message: string } | null };

  const tournamentsPromise: Promise<RpcResult | null> =
    (target === 'tournaments' || target === 'both')
      ? Promise.resolve(
        supabase.rpc('tournaments_semantic_search', { ... }),
      ) as Promise<RpcResult>
      : Promise.resolve(null);
  // rules 도 동일 패턴
  const [tournamentsResult, rulesResult] = await Promise.all([...]);
  ```
- **문제**: `supabase.rpc()` 자체가 이미 PromiseLike<{data,error}> 인데, `Promise.resolve(supabase.rpc(...))` 로 두 번 감싸고 다시 `as` 캐스팅. 의도는 "조건부로 호출"이지만 더 단순한 일반 변수 + if 분기로 충분.
- **권장**:
  ```ts
  const tRes = (target === 'tournaments' || target === 'both')
    ? await supabase.rpc('tournaments_semantic_search', { ... })
    : null;
  const rRes = (target === 'rules' || target === 'both')
    ? await supabase.rpc('rules_semantic_search', { ... })
    : null;

  if (tRes?.error) return errorResponse(tRes.error.message, 500);
  if (rRes?.error) return errorResponse(rRes.error.message, 500);

  return jsonResponse({
    tournaments: tRes?.data ?? [],
    rules: rRes?.data ?? [],
  });
  ```
  순차 호출로 바뀌지만 chat 에서만 호출되며 1초 미만 차이라 무시 가능. 진짜 병렬을 원하면 `Promise.all([tP, rP])` 형태로 `.rpc()` 결과를 직접 배열로 감싸면 충분 (`as` 불필요).
- **영향**: 28줄 → 약 14줄 (**−14줄**). `as` 캐스팅 0개.

---

### [SIMP-05] chat/index.ts 단일 함수가 280줄 (책임 6개)

- **위치**: `supabase/functions/chat/index.ts` 전체 280줄
- **현재 코드 책임 분포**:
  - 1~106 헬퍼 (sseEvent, buildSystemPrompt, buildContextPrompt) — 50줄
  - 108~130 인증 + body 검증 + conversationId 발급
  - 130~150 user_sports / prior 조회 + user message insert
  - 152~190 RAG (embed + parallel rpc) — 38줄
  - 191~232 Gemini 호출 + SSE forward — 42줄
  - 235~262 citation merge + assistant insert — 27줄
- **문제**: ReadableStream 의 start callback 안에 5개 단계가 직렬로 들어가 있어 한 함수가 200줄. 단위 테스트 / 디버그 시 RAG 단독 호출이 어려움.
- **권장**: MVP 단계에서는 **분리할 가치가 모호** — 외부에서 재사용하는 단위가 없고, 단계들이 서로 변수 의존(`tournaments`, `rules`, `assistantText`)이 강하다. 다만 `loadRagContext(supabase, userId, message)` 와 `persistAssistantMessage(supabase, ...)` 두 함수만 추출하면 핵심 흐름이 약 80줄로 줄어듦. 다음 차수에서 권장.
  ```ts
  // 추후 권장 분리:
  async function loadRagContext(supabase, userId, message): Promise<{tournaments, rules}>;
  function buildHistory(prior, contextPrompt, userMessage): ChatTurn[];
  async function persistAssistantMessage(supabase, ..., text, citations);
  ```
- **영향**: 단위 테스트 가능성 향상. 라인 수는 비슷 (분리 비용으로 +10), 가독성/테스트성 향상이 본질.
- **MVP 판단**: **보류**. 현 상태에서 작동 중이고, 한 곳을 보면 끝나는 장점도 있다.

---

### [SIMP-06] tournaments-search/clubs-search/tournament_submit 등 13개 Edge Function 의 boilerplate

- **위치**: 모든 `supabase/functions/*/index.ts`
- **현재 패턴** (13함수 중 8함수가 동일):
  ```ts
  Deno.serve(async (req) => {
    const pre = preflight(req);
    if (pre) return pre;
    if (req.method !== 'POST') return errorResponse('Method not allowed', 405);
    const auth = await requireUser(req);
    if ('error' in auth) return auth.error;
    const { supabase, user } = auth;
    let body: T;
    try { body = await req.json(); } catch { return errorResponse('Invalid JSON body'); }
    // ...실제 로직
  });
  ```
- **문제**: 함수당 약 8줄 × 8함수 = 64줄 boilerplate. 일관되지만 추출 시 시그니처가 복잡 (method 검증, body 파싱, 인증 옵션 분기).
- **권장**: **두 개의 helper 만 추가**:
  ```ts
  // _shared/handler.ts
  export function defineHandler<TBody>(opts: {
    method: 'GET' | 'POST' | 'DELETE';
    auth: 'user' | 'admin' | 'none';
    body?: 'json' | 'none';
    handler: (ctx: { req: Request; user?: AuthedUser; supabase?: SupabaseClient; body?: TBody })
      => Promise<Response>;
  }) {
    return async (req: Request) => {
      const pre = preflight(req);
      if (pre) return pre;
      if (req.method !== opts.method) return errorResponse('Method not allowed', 405);
      let user, supabase;
      if (opts.auth !== 'none') {
        const a = opts.auth === 'admin' ? await requireAdmin(req) : await requireUser(req);
        if ('error' in a) return a.error;
        ({ user, supabase } = a);
      }
      let body: TBody | undefined;
      if (opts.body === 'json') {
        try { body = await req.json(); } catch { return errorResponse('Invalid JSON body'); }
      }
      return opts.handler({ req, user, supabase, body });
    };
  }
  ```
  사용 (`tournaments-submit`):
  ```ts
  Deno.serve(defineHandler<SubmitBody>({
    method: 'POST', auth: 'user', body: 'json',
    handler: async ({ user, supabase, body }) => {
      if (!body!.title?.trim()) return errorResponse('title required');
      // ...
    },
  }));
  ```
- **영향**: 함수당 약 5줄 절약 × 8함수 = **−40줄**, 핸들러 추가 비용 약 +30줄 → 순 −10줄. 라인 수 효과는 적지만 **모든 함수 진입로의 일관성**이 큰 이득. 실수 (preflight 누락, 401 체크 누락 등) 가 0% 가능해진다.
- **MVP 판단**: 이미 작동 중이고 라인수 절감이 미미하므로 **보류 권장**. 단 새 함수 추가 시 즉시 도입.

---

### [SIMP-07] tournaments_screen / clubs_screen 의 동일한 list+search 패턴

- **위치**: `app/lib/screens/clubs_screen.dart`, `app/lib/screens/tournaments/tournaments_screen.dart`
- **현재 코드 공통 구조** (95% 동일):
  ```dart
  class _XScreenState extends ConsumerState<...> {
    String? _sport; String _q = ''; List<X>? _results; bool _loading = false;
    Future<void> _load() async { setState(...); final list = await api.searchX(...);
      if (mounted) setState(...);
    }
    initState() { ...addPostFrameCallback((_) => _load()); }
    build() { Column → TextField + Row(ChoiceChip x3) + ListView }
  }
  ```
  특히 종목 ChoiceChip 3개 (전체/테니스/풋살) 가 두 화면 모두에 12줄씩 동일하게 복붙되어 있다 (clubs 60~86, tournaments 76~102).
- **문제**: 화면 추가 시 매번 동일 패턴 복사. ChoiceChip 의 라벨 ("전체" vs "전체 종목") 만 다르다.
- **권장**: 종목 필터 칩만 위젯으로 추출:
  ```dart
  // app/lib/widgets/sport_filter_chips.dart (신규 ~20줄)
  class SportFilterChips extends StatelessWidget {
    final String? value;                        // null = 전체
    final ValueChanged<String?> onChanged;
    final String allLabel;
    const SportFilterChips({super.key, required this.value, required this.onChanged, this.allLabel = '전체'});
    @override Widget build(...) { /* 3개 ChoiceChip */ }
  }
  ```
- **영향**: 두 화면에서 약 50줄 → 호출 2줄 × 2 = 4줄 + 위젯 20줄. **순 −26줄**.
- **MVP 판단**: 추가 화면(rules 의 종목 탭은 TabBar 라 다름) 가 늘어날 가능성이 낮으므로 **무시 가능**.

---

### [SIMP-08] tournament_detail_screen 이 직접 `_supabase.from('tournaments').select()` 호출

- **위치**: `app/lib/screens/tournaments/tournament_detail_screen.dart` 30~36
- **현재 코드**:
  ```dart
  final row = await supa.from('tournaments').select().eq('id', widget.tournamentId).single();
  setState(() => _t = Tournament.fromJson(row));
  ```
- **문제**: 다른 화면들은 `ApiService` 를 통과하는데 detail 만 supabase 직접 호출. 일관성 깨짐. RLS 가 막아주긴 하지만 layer 우회가 발생.
- **권장**: `ApiService.getTournament(String id)` 추가 (5줄), 호출처 변경 (3줄). 큰 영향은 없지만 **layer 일관성** 측면에서 권장.
- **영향**: 라인 수 변화 거의 없음 (+5/-3). 향후 detail 캐시·prefetch 가 들어갈 자리.

---

### [SIMP-09] api.dart 의 ChatMessage 모델 + approveTournament 가 어디서도 호출되지 않음

- **위치**:
  - `app/lib/models/tournament.dart` 141~163 (`ChatMessage`)
  - `app/lib/services/api.dart` 76~87 (`approveTournament`)
- **현재 코드**: 두 심볼 모두 정의만 있고 `grep -rn "ChatMessage\|approveTournament" app/lib` 결과 정의 외 호출 0건.
- **문제**: `ChatMessage` 모델은 `chat_screen.dart` 가 별도 `_Msg` 클래스를 만들어 사용하므로 dead code. `approveTournament` 는 admin 전용 화면이 아직 없어서 dead code. 사용자 가이드라인 §3 "Surgical Changes — orphan 제거"에 해당.
- **권장**:
  - `ChatMessage` 클래스 23줄 삭제. 향후 chat-history 화면 추가 시 그때 도입.
  - `approveTournament` 12줄 보류 (admin 화면이 곧 들어올 가능성). 제거하지 말고 `// TODO: admin screen` 주석만 남김.
- **영향**: **−23줄** (ChatMessage 만).

---

### [SIMP-10] api.dart 의 `Uri.replace(queryParameters: query?..removeWhere(...))` 부수 변형

- **위치**: `app/lib/services/api.dart` 25~31
- **현재 코드**:
  ```dart
  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(AppConfig.apiBaseUrl);
    return base.replace(
      path: '${base.path}/$path',
      queryParameters: query?..removeWhere((_, v) => v.isEmpty),
    );
  }
  ```
- **문제**: cascade `?..removeWhere` 가 호출자가 넘긴 Map 을 **in-place 변형**한다. 호출처가 인라인 map 리터럴이라 현재는 안전하지만 미묘한 함정. 또한 `query` 가 이미 `if (...) 'k': v` 패턴으로 값 빈 키를 안 넣고 있어 `removeWhere` 자체가 사실상 dead code.
- **권장**:
  ```dart
  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(AppConfig.apiBaseUrl);
    return base.replace(path: '${base.path}/$path', queryParameters: query);
  }
  ```
- **영향**: **−1줄**, side-effect 제거.

---

### [SIMP-11] notify-cron 에서 `(favorites as any[])` cast — 타입 누수

- **위치**: `supabase/functions/notify-cron/index.ts` 70
- **현재 코드**:
  ```ts
  // deno-lint-ignore no-explicit-any
  const tasks: NotifyTask[] = ((favorites as any[]) ?? [])
    .flatMap((f) => { ... });
  ```
- **문제**: `tournaments!inner(...)` 조인 결과 타입을 SDK 가 추론 못해 `any[]` 캐스팅. 위 RAG/semantic-search 등에서는 명시 인터페이스를 만들었는데 여기만 `any`. 일관성 부족.
- **권장**: `interface FavoriteRow { user_id: string; tournament_id: string; tournaments: { id: string; title: string; start_date: string; application_deadline: string | null; status: string } }` 추가, 캐스팅을 `(favorites ?? []) as FavoriteRow[]` 로 변경.
- **영향**: **+5줄, −1줄** (lint-ignore 제거). 안전성 향상.

---

### [SIMP-12] router.dart 의 onboarding redirect 로직 모호

- **위치**: `app/lib/router.dart` 30~34
- **현재 코드**:
  ```dart
  final sports = ref.read(userSportsProvider).valueOrNull;
  if ((sports == null || sports.isEmpty) && loc != '/onboarding') {
    // sports 가 아직 로딩 중이면 온보딩으로 보내지 않음
    if (sports != null && sports.isEmpty) return '/onboarding';
  }
  ```
- **문제**: 외부 if 와 내부 if 가 동일 조건 일부를 다시 검사해서 외부 if 의 `sports == null` 가지가 무용지물. 의도는 "loading=null 이면 무시, empty 면 /onboarding". 그냥 한 줄로:
  ```dart
  if (sports != null && sports.isEmpty && loc != '/onboarding') return '/onboarding';
  ```
- **권장**: 5줄 → 1줄. 같은 의미.
- **영향**: **−4줄**, 의도 명확.

---

### [SIMP-13] 008_cron 의 `current_setting('app.cron_invoke_url', true)` GUC 패턴

- **위치**: `supabase/migrations/008_cron.sql` 13~40
- **현재 코드**: `invoke_edge_function(fn_name, body)` 가 GUC 두 개를 매번 읽어 `pg_net.http_post` 호출.
- **문제**: 함수 자체는 단순. **다만 5개의 cron schedule 항목이 동일 패턴 반복** (`select public.invoke_edge_function('xxx');`). Postgres 함수 한 개로 일원화되어 있어 boilerplate 자체는 이미 최소.
- **권장**: 그대로 둠. **MVP에서 추가 단순화 불필요**. 다만 `current_setting('app.cron_invoke_url', true)` 의 두 번째 인자 `true`(missing OK) 의도가 주석에 안 적혀 있어 한 줄 주석 추천.
- **영향**: 0줄 변화. 결정: **무시**.

---

### [SIMP-14] gemini.ts 의 `parts: ChatPart[]` 타입은 외부에서 매번 `[{ text: ... }]`만 사용

- **위치**: `supabase/functions/_shared/gemini.ts` 16~23 + `chat/index.ts` 196~213
- **현재 코드**:
  ```ts
  export interface ChatPart { text: string; }
  export interface ChatTurn { role: 'user' | 'model'; parts: ChatPart[]; }
  // 호출 5번 모두: history.push({ role: 'user', parts: [{ text: '...' }] });
  ```
- **문제**: parts 가 항상 단일 텍스트 part 1개. Gemini multi-modal/multi-part 를 안 쓰는데 배열 wrapping 5곳에 노출.
- **권장**: helper 추가
  ```ts
  // gemini.ts
  export const userTurn = (text: string): ChatTurn => ({ role: 'user', parts: [{ text }] });
  export const modelTurn = (text: string): ChatTurn => ({ role: 'model', parts: [{ text }] });
  ```
- **영향**: chat/index.ts 약 −5줄, 가독성 향상. **MVP 판단: 무시 가능**, 코드 자체가 이미 짧음.

---

## 우선순위 분류

### 즉시 (Quick wins, 영향 큼/리스크 낮음)
- **[SIMP-01]** 3개 크롤러 중복 → `runTennisCrawler` helper 추출 (**−160줄**, 리스크 낮음)
- **[SIMP-02]** `canEnter`, `rankOf`, `TENNIS_RANK`, `FUTSAL_RANK` 삭제 (**−45줄**, 0 호출처라 무리스크)
- **[SIMP-09]** `ChatMessage` 모델 삭제 (**−23줄**, 0 호출처)
- **[SIMP-12]** router 의 redirect 4줄 → 1줄 (**−4줄**, 의미 동일)
- **[SIMP-04]** semantic-search RpcResult 캐스팅 단순화 (**−14줄**)
- **[SIMP-10]** api.dart `_uri` 의 in-place removeWhere 제거 (**−1줄**, 미묘한 버그 함정 제거)

**소계: 약 −247줄, 리스크 ~0**

### 중기 (리팩토링 필요)
- **[SIMP-03]** Sport enum 사용을 onboarding 으로 국한 (호출처 6곳 일괄 수정)
- **[SIMP-05]** chat/index.ts 의 RAG/persist helper 추출 (테스트 작성 시점에 같이)
- **[SIMP-08]** tournament_detail 의 supabase 직접 호출을 ApiService 로 (layer 일관성)
- **[SIMP-11]** notify-cron 의 `any[]` 캐스팅을 인터페이스로

### 무시 가능 (취향)
- **[SIMP-06]** 13개 함수 boilerplate `defineHandler` (현재 일관되어 있고 라인 절감 미미)
- **[SIMP-07]** `SportFilterChips` 위젯 추출 (화면 2개라 임계점 못 미침)
- **[SIMP-13]** 008_cron 의 GUC 함수 (이미 단순)
- **[SIMP-14]** gemini.ts `userTurn`/`modelTurn` helper (취향)

---

## 결론

**Match-up MVP 코드는 대체로 이미 단순하며 사용자의 `Simplicity First` 가이드라인을 잘 따르고 있다.** 약 5,000줄 중에서 **약 −170줄(3.4%) 만이 곧바로 정리 가능**하고, 그중 핵심은:

1. **3개 크롤러의 boilerplate 가 95% 동일**하다는 점 (SIMP-01) — 4번째 사이트가 추가되기 전에 처리해야 함
2. **`enums.ts` 의 미사용 helper 20여 줄** (SIMP-02, 09) — "추측성 추상화" 가이드라인의 직접 위반
3. **단순화 가능한 micro-패턴 4개** (SIMP-04, 10, 12, 14)

MVP 단계에서는 **즉시 군 (SIMP-01/02/09/12/04/10) 만** 처리하고 나머지는 보류해도 무방하다. 특히 SIMP-06 의 `defineHandler` 패턴은 현재 13함수가 일관되어 있어 추가 추상화 비용이 절감보다 크고, SIMP-05 의 chat 분해는 단위 테스트가 들어올 때 함께 처리하는 것이 자연스럽다.

**단 한 줄 권장**: `enums.ts` 의 `canEnter` 와 `rankOf` 는 **다음 PR 에서 즉시 삭제**하라. 이것이 codebase 에 남아 있는 한 다른 개발자가 "등급 매칭 로직은 TS helper 에도 있겠네" 라고 잘못 가정할 수 있다 — 실제로는 RPC `tournaments_for_user` 만이 단일 진실 원천이다.
