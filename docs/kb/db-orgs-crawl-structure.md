# DB 구조 — 테니스 협회·등급 & 크롤링 파이프라인

> 조사일 2026-07-15 (드론, 서브에이전트 2종 병렬). 프로덕션 `bsjdgwmveokanclqwtvx` 실측 + 코드/마이그레이션 근거.
> 목적: 협회 확충(JY-135)·크롤링 이해를 위한 전체 데이터 흐름 정리. 백과장·시리 공용.

## 0. 한눈에 — 데이터 흐름 & 접점

```
[크롤링]  대회 사이트 ──parser──▶ tournaments (status='draft')
           · org           = crawl_sources.org_code (그대로, 추론 안 함)
           · eligible_grades = tennis_divisions.synonyms 를 본문에 substring 매칭 (크롤 단계 자동)
                              │ 관리자 draft→published 승인(신뢰 게이트, 매칭 아님)
                              ▼
[사용자]  온보딩 ──▶ user_tennis_orgs
           · division       = "마스터즈부 · 지도자부" (라벨 텍스트)   ✅ 저장됨
           · division_codes = []                                    🔴 저장 안 됨 (버그)
                              ▼
[매칭 RPC] expand_division_codes(division_codes) ∩ eligible_grades  → 사용자 대회 추천
           (equiv_group 으로 협회 경계 넘어 동치 확장; 마이그레이션 072/085)
                              ↑ 사용자 division_codes 가 비어 교집합 항상 0 → 테니스 추천 0건
```

## 1. 협회·등급 도메인

| 테이블 | 역할 | 핵심 컬럼 | FK |
|---|---|---|---|
| `tennis_orgs` (10) | 협회 디렉터리 | code(PK)·name_ko·org_type(national/sido/sigungu/club)·region_code·**division_scheme**·is_active | region_code→regions |
| `tennis_divisions` (58) | 부서 사전 = eligible_grades 정본 | code(PK,`{org}_{suffix}`)·org_code·label_ko·**synonyms[]**·skill_tier·gender·age_min·**equiv_group** | org_code→tennis_orgs |
| `user_tennis_orgs` (4) | 사용자↔협회 소속 | user_id·org·**division**(라벨 텍스트)·**division_codes[]**(코드)·score·region_code | user_id→users, org→tennis_orgs |
| `user_sports` (9) | 사용자↔종목·경력등급 | user_id·sport(tennis/futsal)·grade(under1y/y1to3/y3to5/over5y)·is_primary | user_id→users |
| `regions` (21) | 광역시도(17 활성+deprecated) | code(PK)·display_name_ko·governing_associations[]·uses_kato/kata | — |

- **division_scheme**: 협회의 부서 체계 그룹 태그(`sido_std`, `kta`, `kata`, `kstf_senior`, `local`). gj·jn 이 `sido_std` 공유. 현재 문서/그룹핑용, 매칭에 직접 안 씀.
- **equiv_group**: 협회 경계 넘는 동치 부서(`sido_std:m_gold` → 광주·전남 교차, `senior:60` → kta_senior_60·kstf_60). 매칭 RPC 의 `expand_division_codes()` 가 사용.
- **grade vs division**: 별개 체계. **테니스 대회 자격은 grade 가 아니라 division_codes 로 판정**(마이그레이션 072). grade 는 테니스에선 표시·온보딩용. 풋살은 grade 직접 비교.

### 온보딩 선택지 데이터 소스 (협회 확충의 관건)
- **부서(division) = DB 로드**: `DivisionCatalog.load()` 가 앱 시작 시 `tennis_divisions`(is_active) 를 읽어 카탈로그 교체(실패 시 const fallback). → **`tennis_divisions` INSERT 만으로 앱 반영, 재배포 불필요.** (KATO 10개 부서가 DB에만 있고 앱에 보이는 것이 방증.)
- **협회(org) = Dart 하드코딩**: 온보딩 협회 목록·라벨이 `enums.ts`/`grade_labels.dart` 의 `tennisOrgs`/`tennisOrgLabels` 상수. `tennis_orgs` 테이블 미참조. → **협회 추가는 코드 수정 + 앱 재배포 필요.** (협회 테이블화는 미완 상태.)

## 2. 크롤링 파이프라인

```
pg_cron(15~30분) 또는 어드민 수동(force) → crawl-dispatch(단일 진입점)
  → crawl_sources 스케줄·lock 평가 → parser(kato-openlist | gnuboard) 실행
  → 목록 fetch(ETag 304면 skip) → 활성 대회 상세 fetch(≤30)
  → buildTournament(+mapDivisionsByDict) → upsertTournament
       ├─▶ tournaments (UPSERT, 신규 status='draft')
       └─▶ crawl_documents (원본 HTML raw)
  → crawl_audit(run 로그) + crawl_sources 메트릭 UPDATE
```

| 테이블 | 행수 | 역할 | 크롤러가 쓰나 |
|---|---|---|---|
| `crawl_sources` | 9 | 출처+스케줄·메트릭(last_etag·crawl_running lock) | 읽고 메트릭 write |
| `crawl_documents` | 50 | 상세 원본 HTML(content_hash SHA-256, UNIQUE(source,url)) | ✅ write |
| `crawl_audit` | 4252 | 실행 감사 로그(run당 1행) — 대회 데이터 아님 | ✅ write |
| `tournaments` | 73 | 대회 코어(eligible_grades[]·division_label_local·status·source_url) | ✅ write |
| `tennis_tournament_details` | 34 | 테니스 확장 1:1 (tournament_id PK→tournaments, CASCADE) | ❌ seed/제보 |
| `futsal_tournament_details` | 30 | 풋살 확장 1:1 | ❌ seed(071) |
| `venues` | 269 | 경기장 카탈로그(전부 source='futsal.or.kr' seed) | ❌ seed(046b), FK 없음(location 자유텍스트) |

- **org/grade 채우기**: org=`crawl_sources.org_code` 그대로(추론 금지). grade=`tennis_divisions.synonyms` substring 매칭(크롤 자동). 미매칭 시 codes=[]·draft 로 검수 대기. **관리자는 승인만, 매칭 안 함.**
- **synonyms vs equiv_group**: synonyms→파서 매칭, equiv_group→검색 RPC 등급 동치. 파서는 code·synonyms·label_ko 3컬럼만 로드.
- **풋살 크롤 미가동**: 5개 futsal crawl_sources 전부 `enabled=false`. 풋살 대회·경기장은 seed 만.
- **재크롤**: ETag/Last-Modified(304) → content-hash 폴백 → 문서 content_hash. `force=true` 로 전량 재크롤(last_etag 비우기 = 동일 효과).

## 3. 발견 사항

### 🔴 A. 테니스 대회 자격매칭 무력화 (출시 크리티컬 — JY-136)
온보딩이 `user_tennis_orgs.division_codes` 를 저장 안 함. `UserTennisOrg`(tournament.dart) 모델에 divisionCodes 필드 자체가 없어 `toUpsert`/`fromJson` 에서 누락 → 부서를 골라도 라벨(`division`)만 저장, `division_codes=[]`. 테니스 매칭 RPC 는 division_codes 교집합만 보므로 **"내 등급 대회" 필터에서 테니스 대회 0건**. demian 실데이터도 codes=[].
→ 수정: UserTennisOrg 에 divisionCodes 필드 + toUpsert/fromJson 반영 + 온보딩 저장 시 선택 코드 전달 + 기존 사용자 백필(라벨→코드).

### B. 협회 확충 (JY-135)
부서=DB INSERT 만, 협회=DB+코드+재배포. 시도협회는 `sido_std` 표준 재사용 가능(gj/jn 패턴 복제).

### C. 풋살 크롤 파이프라인 미가동
seed 기반. 크롤 활성화는 파서·소스 enable 필요(출시 후).
