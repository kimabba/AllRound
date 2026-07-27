# Match-up MVP QA 체크리스트

> 출시 전 수동/자동 QA 게이트. Linear `JY-8`(전체 E2E)·`JY-9`(푸시·어드민 QA) 산출물.
> 자동 검증(🤖)은 Claude Code가, 실기기(🧑)는 사람이 수행한다. 발견 버그는 Linear 이슈로 등록.

마지막 수행: 2026-06-10

## 범례
- ✅ 통과 / ⚠️ 결함 발견(이슈화) / ⬜ 미수행 / 🚧 차단(선행 필요)

---

## A. 데이터 품질 (🤖 Supabase 직접 쿼리)

| 항목 | 상태 | 비고 |
|---|---|---|
| tournaments: start_date/region/eligible_grades/source_url/title 결손 | ✅ | 0건 |
| tournaments: `region_code` 채움 + region 정합 | ✅ | **버그 발견·수정** — 크롤러 누락 → PR #32 (백필 33건, 오매칭 1건 교정) |
| tournaments: 마감일 누락 | ⚠️ | 1건 (closed 상태, 영향 낮음 — 확인 필요) |
| clubs / club_events / club_members 정합성 | ⬜ | Supabase 연결 복구 후 |
| venues: region_code / sport 정합성 | ⬜ | 〃 |
| rule_articles: embedding 채움 (published) | ⬜ | 〃 |
| profiles: active_sport 정합성 | ⬜ | 〃 |
| Supabase advisor (security: RLS/정책 누락) | ⬜ | `get_advisors security` |
| Supabase advisor (performance: 인덱스 누락) | ⬜ | `get_advisors performance` |

## B. 코드레벨 — 에러/빈/로딩 상태 (🤖 소스 점검)

| 화면 | 상태 | 비고 |
|---|---|---|
| club_detail (멤버·이벤트 FutureBuilder) | ✅ | waiting/hasError/isEmpty 전부 처리 |
| tournaments_screen (검색 결과 + 맞춤 추천) | ✅ | 메인=명시 빈/에러 처리, 추천=의도적 숨김 |
| profile / knowledge_base / admin_shell (`AsyncValue.when`) | ✅ | error 인자 컴파일러 강제 |
| chat_screen (SSE 스트림 에러/중단 처리) | ⬜ | 미점검 |
| tournament_detail (PR 후 1093줄 대규모 변경) | ⬜ | 미점검 — 신규 코드 우선 |
| 어드민 화면 (검수 큐 빈/에러) | ⬜ | 미점검 |

## C. 어드민 웹 (🤖 `make admin` = flutter run -d chrome)

| 항목 | 상태 |
|---|---|
| 비어드민 웹 접속 → no_access 안내 | ⬜ |
| 검수 큐: draft 목록 / 승인·거절 / 일괄 처리 | ⬜ |
| 크롤 소스 CRUD + 수동 실행 | ⬜ |
| 클럽 승인/거절 | ⬜ |
| 지식베이스: 룰 CRUD / 게시 / 임베딩 재계산 | ⬜ |
| 대회 수기 편집 (TournamentEditScreen) | ⬜ |

## D. 앱 사용자 동선 E2E (🧑 실기기 iOS/Android)

| 동선 | 상태 |
|---|---|
| 가입 → 온보딩(종목/등급) → 홈 진입 | ⬜ |
| 종목 스왑 (테니스 ↔ 풋살) 전체 화면 반영 | ⬜ |
| **종목/등급 저장이 실기기에서 성공** (#320 권한 회수 후 · RPC 경계) | ⬜ **꼭 체크** — 서버 경로는 2026-07-25 운영 DB 실측 통과(authenticated→RPC 성공, 직접 DML 42501 차단). 남은 건 UI 레이어뿐 |
| 등급 선택지가 채워짐 (grades DB 조회 · 로그인 후) | ⬜ 로그인 전에는 `grades_read` 정책상 빈 목록 |
| 대회 검색 → 필터 → 상세 → 즐겨찾기 → 제보 | ⬜ |
| 클럽 생성 → 승인 → 가입 신청 → 상세(멤버/모임/참석) | ⬜ |
| 챗봇: 대회 검색 / 규칙 / 구장 / 잡담 intent | ⬜ |
| 더보기: 프로필 / 룰북 / 약관 | ⬜ |
| 에러·빈·로딩·다크모드 시각 점검 | ⬜ |

## E. 푸시 알림 (🧑 실기기) — 🚧 차단

| 항목 | 상태 |
|---|---|
| FCM Server Key 설정 (`JY-43` 선행) | 🚧 미설정 — 키 없으면 발송 `failed`만 기록 |
| D-3 즐겨찾기 알림 수신 | 🚧 |
| 신청 마감 알림 수신 | 🚧 |

---

## 발견 버그 로그

| 일자 | 항목 | 조치 |
|---|---|---|
| 2026-06-10 | tournaments.region_code 전량 null → 지역 필터 무력 + 오매칭 1건 | crawler 매핑 + 백필 (PR #32, 머지) |

## 다음 수행 시
1. Supabase 연결 후 A 섹션 나머지(테이블 정합성 + advisor) 완료.
2. `make admin`으로 C 섹션 어드민 웹 클릭 테스트.
3. 실기기 확보 후 D 섹션 E2E. 푸시(E)는 `JY-43` 완료 후.
