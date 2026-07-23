# 페르소나 챗봇 시뮬레이션 (synthetic user testing)

로컬 Supabase 스택에 다양한 직군·연령·성향의 **합성 사용자(페르소나)**를 실제로
가입시켜, 앱 기능과 AI 챗봇을 "실사용자처럼" 테스트하고 UX·정확도 findings를 모은다.
페르소나 브레인은 가성비 모델(Claude Haiku)로 돌려 Gemini 챗봇 쿼터와 분리한다.

## 구성
- `sim.ts` — 기계부 CLI (Deno). signup / onboard / UGC약관 / clubs / tournaments / chat(SSE 파싱, 429 재시도)
  - `deno run -A sim.ts setup '<persona-json>'` → 가입~대회 전 여정, `{token,uid,steps}` 출력
  - `deno run -A sim.ts chat <token> "<질문>" [sport]` → 채팅 1턴 `{intent,answer,error}`
  - `deno run -A sim.ts journey '<persona-json>'` → setup + persona.questions 로 채팅(비적응형)
- `personas_20.json` (테니스 10 + 풋살 10), `personas_pilot.json` (4명) — 페르소나 정의. `persona` 필드가 Haiku 브레인 시드.

## 실행 (0부터)
```bash
supabase start                       # 내장 edge 런타임이 함수 서빙 + functions/.env의 GEMINI_API_KEY 로드
export ANON_KEY=$(supabase status -o env | grep ANON_KEY | cut -d'"' -f2)
```

### 1) 임베딩·intent 시드 (채팅 RAG/분류에 필요, admin JWT 필요)
채팅 검색·intent 분류는 임베딩에 의존한다. `seed-intent-examples`·`embed-pending`은
레거시 service_role JWT를 **거부**하므로 **admin 유저 JWT**로 호출한다.
```bash
# admin 유저 생성(birth_date 필수) → SQL로 승격
RESP=$(curl -s -X POST "http://127.0.0.1:54321/auth/v1/signup" -H "apikey: $ANON_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"email":"sim-admin@example.com","password":"Passw0rd!23","data":{"birth_date":"1988-05-05"}}')
AID=$(echo "$RESP" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
ATOK=$(echo "$RESP" | grep -o '"access_token":"[^"]*"' | head -1 | cut -d'"' -f4)
docker exec supabase_db_matchup psql -U postgres -d postgres -c "update users set role='admin' where id='$AID';"
curl -s -X POST "http://127.0.0.1:54321/functions/v1/seed-intent-examples" -H "Authorization: Bearer $ATOK"
for i in 1 2 3 4 5; do curl -s -X POST "http://127.0.0.1:54321/functions/v1/embed-pending" -H "Authorization: Bearer $ATOK"; done
```
⚠️ Gemini 무료티어 임베딩 **100 RPM** — 429 나오면 ~30초 뒤 재시도.

### 2) 로컬 스키마 응급수정 (클린 재생 드리프트)
마이그레이션을 처음부터 재생하면 `tournaments_semantic_search`가 **중복 오버로드**로
남아 PostgREST 모호성 → 채팅 대회검색이 깨진다(prod는 오버로드 1개라 무영향).
```bash
docker exec supabase_db_matchup psql -U postgres -d postgres -c \
  "DROP FUNCTION IF EXISTS public.tournaments_semantic_search(uuid,vector,boolean,text,integer); NOTIFY pgrst,'reload schema';"
```

### 3) 페르소나 실행
```bash
# 개별
deno run -A sim.ts setup "$(deno eval 'console.log(JSON.stringify(JSON.parse(Deno.readTextFileSync("personas_20.json"))[0]))')"
# 20명 적응형: setup ×20 으로 토큰 모은 뒤 Claude Code Workflow 로 Haiku 페르소나 팬아웃
# (지난 세션 워크플로우 스크립트: persona-chat-simulation. args 는 문자열로 넘어오니 JSON.parse 가드 필요)
```

## 함정 (계약)
- 가입: `user_metadata.birth_date` 필수 (before-user hook, 14세+ 검증)
- 온보딩 grade 값: 테니스 `under1y/y1to3/y3to5/over5y`, 풋살 `intro/beginner/intermediate/advanced/elite`
- `user_tennis_orgs.division`(단수) NOT NULL + `division_codes`(배열)
- `clubs-join` 전 `rpc/accept_current_ugc_terms` 동의 필수(안 하면 403 `UGC_TERMS_REQUIRED`)
- 채팅 대회검색 intent는 **종목 등록 후에만** 응답
- 미승인(pending) 클럽은 검색에서 정상 숨김

## 지금까지 (2026-07-22 세션)
- **머지된 fix**: #293 (채팅 `p_region` 오호출 → "대회 미구현" 오안내), #294 (intent 오분류: "대회 규정"→rule_lookup, "클럽 개설"→검색 제외)
- 20명 시뮬 findings 요약: intent 오분류(일부는 빈 intent_examples 로컬 아티팩트), 구체정보/카드 불만(하니스가 텍스트 전용이라 카드 미렌더 — B그룹), 후반 401, 풋살 클럽 pending

## 남은 작업 (이어서)
1. **카드 렌더링 검증** — 앱 실행(`make app`) 또는 컴퓨터유스로 대회/클럽 카드가 날짜·참가비와 함께 렌더되는지 확인 (하니스로는 못 봄, 최우선 추천)
2. **후반 401 규명** — 챗봇 per-user 레이트리밋 vs 세션 만료 (chat rate_limit 로직 확인)
3. **마이그레이션 #4** — `tournaments_semantic_search` 중복 오버로드 정본 판단 후 클린업 PR
4. **"시니어 대회 나이 기준"** 등 대회+자격 모호 케이스 재검토(이번 #294에서 제외)
5. intent_examples 시드를 seed 스크립트/CI 자동화에 편입 검토

## 참고 메모리 (이 머신 로컬 `~/.claude`, mini엔 없을 수 있음)
`local-persona-simulation`, `deno-fake-seam-testing`, `deploy-migration-gotcha`, `nationwide-tennis-schema`
