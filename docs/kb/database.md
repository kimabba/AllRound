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
| birth_date | date? | 이메일 가입 시 Auth Hook 검증 후 트리거가 즉시 저장 |

### 가입 전 Auth 경계
- `before_user_created_allround(event jsonb)` — 이메일 생년월일 누락·형식 오류·만 14세 미만을 `auth.users` INSERT 전에 거부
- 신규 Google identity는 검증된 생년월일 전달 경로가 마련될 때까지 거부하며 기존 Google identity 로그인은 유지
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
| 풋살 전용 | | entry_fee_unit, player_count, venue_type, surface_type 등 |

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

### 기타 테이블
- `chat_messages` — 대화 이력
- `chat_rate_limit` — 챗봇 요청 제한
- `tournament_favorites` — 즐겨찾기
- `device_tokens` — FCM 토큰
- `notifications_log` — 알림 이력 (중복 방지 unique key)
- `crawl_audit` — 크롤 실행 감사 로그
- `regions` — 권역 (8개 시드)
- `rule_articles` — 스포츠 룰북 컨텐츠
- `intent_examples` — 챗봇 의도 분류 예시
- `qa_cache` — 챗봇 응답 캐시

## 주요 트리거
- `update_club_member_count` — club_members 변경 시 clubs.member_count 자동 갱신

## RLS 정책 요약
- tournaments: published만 일반 공개, admin은 전체
- clubs: approved만 일반 공개, admin은 전체
- club_members: 본인 + 같은 클럽 멤버만 조회
- club_join_requests: 본인 + 해당 클럽 owner/manager만 조회
- crawl_sources: admin only

## 마이그레이션 이력 (최근)
- 029: division_codes_reset_eligible_grades
- 030: invoke_edge_function_internal_cron_jwt
- 031: club_management (clubs status + club_members + club_join_requests + RLS)
