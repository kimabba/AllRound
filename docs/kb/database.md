# 데이터베이스 스키마

Project ref: `bsjdgwmveokanclqwtvx`

## 핵심 테이블

### users
| 컬럼 | 타입 | 설명 |
|---|---|---|
| id | uuid PK | auth.users FK |
| email | text | |
| display_name | text? | |
| role | user_role | 'user' \| 'admin' |
| birth_date | date? | 이메일 가입은 Auth Hook 검증 후 즉시 저장, Google 신규 가입은 온보딩에서 저장 |

### 가입 전 Auth 경계
- `before_user_created_allround(event jsonb)` — 이메일 생년월일 누락·형식 오류·만 14세 미만을 `auth.users` INSERT 전에 거부
- 신규 Google identity는 빈 profile 생성을 허용하고, 온보딩 저장 전에는 `has_verified_signup_age()` 기반 RLS·Edge guard로 핵심 쓰기를 차단
- 함수 실행권한은 `supabase_auth_admin`에만 부여하고 앱의 `anon`/`authenticated` 역할에는 부여하지 않음

### user_sports
사용자 종목·등급 등록 (복수 가능)
| 컬럼 | 타입 | 설명 |
|---|---|---|
| user_id | uuid PK | |
| sport | sport_type PK | tennis \| futsal |
| grade | text | 등급 코드 |
| is_primary | bool | 주 종목 여부 |

### user_tennis_orgs
테니스 협회별 등급 (복수 협회 등록 가능)
| 컬럼 | 타입 | 설명 |
|---|---|---|
| user_id | uuid PK | |
| org | tennis_org PK | gj, jn, kta, kata, ktfs, kstf, local |
| division_local | text? | 해당 협회 부서명 |
| score | numeric? | 랭킹 점수 |
| is_primary | bool | 주 협회 여부 |
| region_code | text? | 지역 코드 |

### tournaments
| 컬럼 | 타입 | 설명 |
|---|---|---|
| id | uuid PK | |
| sport | sport_type | |
| title, organizer, description | text | |
| start_date, end_date, application_deadline | date | |
| region, location | text? | |
| eligible_grades | text[] | 부서코드 배열 (gj_m_gold 등) |
| division_label_local | text? | 크롤러 원본 부서명 ("골드부 · 일반부") |
| status | tournament_status | draft → published \| rejected |
| embedding | vector(768)? | RAG용 임베딩 |
| host_orgs | tennis_org[] | 주최 협회 |
| host_futsal_orgs | futsal_org[] | 풋살 주최 협회 |
| source, source_url | text? | 크롤 출처 |
| regulation_document | jsonb? | 공통 요강 문서 AST (`schema_version=1`, 고정 섹션/블록) |
| regulation_schema_version | smallint? | 요강 문서 계약 버전. 문서가 없으면 NULL |
| regulation_fields, regulation_notes, regulation_body | jsonb/text[]/text? | 구버전 앱·검색 호환용 파생 요강 |
| 풋살 전용 | | entry_fee_unit, player_count, venue_type, surface_type 등 |

### tournament_submission_contacts
사용자가 제보한 대회의 담당자 개인정보를 공개 대회 행과 분리해 보관한다.
| 컬럼 | 타입 | 설명 |
|---|---|---|
| tournament_id | uuid PK | tournaments FK, 대회 삭제 시 함께 삭제 |
| submitted_by | uuid | 제보자 users FK, 계정 삭제 시 함께 삭제 |
| contact_name | text | 담당자 이름 |
| contact_value | text | 관리자 확인용 전화번호 또는 이메일 |
| created_at | timestamptz | 저장 시각 |

### clubs
| 컬럼 | 타입 | 설명 |
|---|---|---|
| id | uuid PK | |
| sport | sport_type | |
| name, region?, address?, contact?, website?, description? | text | |
| status | text | pending → approved \| rejected |
| status_reason | text? | 거절 사유 |
| created_by | uuid? | 생성 요청자 |
| approved_by, approved_at | | 승인자·시점 |
| member_count | int | 트리거로 자동 갱신 |
| active | bool | (레거시, status로 대체) |

### club_members
| 컬럼 | 타입 | 설명 |
|---|---|---|
| id | uuid PK | |
| club_id, user_id | uuid | UNIQUE(club_id, user_id) |
| role | text | owner \| manager \| member |
| status | text | active \| left \| banned |
| joined_at, left_at | timestamptz | |

### club_join_requests
| 컬럼 | 타입 | 설명 |
|---|---|---|
| id | uuid PK | |
| club_id, user_id | uuid | UNIQUE(club_id, user_id) |
| message | text? | 가입 메시지 |
| status | text | pending → approved \| rejected |
| reviewed_by, reviewed_at | | 처리자·시점 |

### crawl_sources
DB-driven 크롤러 소스 정의
| 컬럼 | 타입 | 설명 |
|---|---|---|
| slug | text UNIQUE | 코드 식별자 |
| url | text | listing URL |
| parser_module | text | 파서 모듈명 |
| schedule_cron | text | cron 표현식 |
| enabled | bool | |
| last_crawled_at, last_status, last_error | | 최근 실행 상태 |

### 협회 랭킹과 선수 이력

| 테이블 | 설명 |
|---|---|
| `org_rankings` | 협회·부서별 현재 순위, 선수명, 소속, 포인트 |
| `org_ranking_snapshots` | 본인 연결 선수의 랭킹 변동 기록 |
| `org_player_results` | 협회가 공표한 선수별 대회명·일자·종목·성적·포인트 |
| `org_player_history_fetches` | 선수 상세 온디맨드 수집 시각·건수·완전 수집 여부 |

`ranking-player-history` Edge Function은 로그인 사용자에게 현재 랭킹에 있는 선수만
허용하고, 첫 상세 조회 때 원본을 가져온 뒤 24시간 동안 캐시를 재사용한다. 선수별
이력의 기존 본인 전용 RLS는 넓히지 않으며 Edge Function이 응답 범위를 통제한다.

### 기타 테이블
- `chat_messages` — 대화 이력
- `chat_rate_limit` — 챗봇 요청 제한
- `tournament_favorites` — 즐겨찾기
- `device_tokens` — FCM 토큰
- `notifications_log` — 알림 이력 (중복 방지 unique key)
- `crawl_audit` — 크롤 실행 감사 로그
- `regions` — 권역 (8개 시드)
- `rule_articles` — 스포츠 룰북 콘텐츠. 2026-08-19 기준 게시 글은 테니스 33건(기존 랭킹 규정), 풋살 30건(FIFA 현행 풋살 법칙 기준)이다. 검수 전인 ITF 2026 테니스 요약 18건은 준모의 도메인 검토 전까지 비게시 상태로 보존한다. 풋살은 경기 규칙·운영·장비·포지션 중심으로 노출하며 홍보·훈련·건강 가이드는 게시 해제했다. 보강 글 본문에는 공식 출처 URL을 남긴다.
- `rule_article_clicks` — 룰북 유효 클릭 기록(사용자·규칙별 최근 24시간 중복 제거, 인기 카드 집계용)
- `intent_examples` — 챗봇 의도 분류 예시
- `qa_cache` — 챗봇 응답 캐시

## 주요 트리거
- `update_club_member_count` — club_members 변경 시 clubs.member_count 자동 갱신

## RLS 정책 요약
- tournaments: published만 일반 공개, admin은 전체
- tournament_submission_contacts: 제보자 본인과 admin만 조회, 쓰기는 Edge Function의 service role만 허용
- clubs: approved만 일반 공개, admin은 전체
- club_members: 본인 + 같은 클럽 멤버만 조회
- club_join_requests: 본인 + 해당 클럽 owner/manager만 조회
- crawl_sources: admin only
- org_player_results: 본인 연결 선수 + admin만 직접 조회
- org_player_history_fetches: service role만 실제 행 조회·수정

## 마이그레이션 이력 (최근)
- 029: division_codes_reset_eligible_grades
- 030: invoke_edge_function_internal_cron_jwt
- 031: club_management (clubs status + club_members + club_join_requests + RLS)
- 20260819080000: 최근 24시간 룰북 클릭 집계와 종목별 인기 규칙 RPC 추가
- 20260819090000: ITF 2026 테니스 규칙 보강, FIFA 현행 풋살 누락 규칙 추가 및 골키퍼·카드 설명 오류 수정
- 20260819100000: 풋살 룰북을 경기 규정 중심 30건으로 정리
- 20260819110000: 풋살 경기장 글을 실제 규격 수치 중심으로 보완
- 20260819120000: 준모 검수 전 ITF 2026 테니스 요약 18건을 비게시 보관
