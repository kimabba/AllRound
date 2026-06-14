# DB 재설계 진행 현황

> 마지막 업데이트: 2026-06-14
> 다음 세션에서 이 파일부터 읽고 이어서 진행

## 설계 순서

```
Layer 0: users                    ✅ 확정
Layer 1: user_sports              ✅ 확정 (현행 유지)
Layer 1: user_tennis_orgs         🔶 검토 중 (컬럼 추가 논의)
Layer 2: tournaments              ⬜ 미시작
Layer 2: clubs                    ⬜ 미시작
Layer 3: club_members             ⬜ 미시작 (권한 컬럼 추가 확정)
Layer 4: club_events, club_posts  ⬜ 미시작
Layer 5: notifications            ⬜ 미시작
Layer 6: match_records, rankings  ⬜ 미시작
Layer 7: friendships, schedules   ⬜ 미시작
```

## Layer 0: users — 확정

```sql
users (
  id                uuid PK (= auth.users.id)
  email             text NOT NULL
  name              text NOT NULL          -- 실명 (기존 display_name → name)
  nickname          text                   -- 닉네임 (선택)
  avatar_url        text                   -- 프로필 사진 (서버 저장)
  phone             text                   -- 연락처
  birth_year        int                    -- 출생 연도
  gender            text CHECK (male|female)
  bio               text                   -- 자기소개
  primary_region    text FK → regions      -- 주 활동 지역
  interest_regions  text[] CHECK (max 3)   -- 관심 지역
  role              user_role (user|admin)
  created_at        timestamptz
  updated_at        timestamptz
)
```

변경점: display_name → name, nickname/avatar_url/phone/birth_year/gender/bio/primary_region/interest_regions 추가

## Layer 1: user_sports — 확정 (현행 유지)

```sql
user_sports (
  user_id    uuid FK
  sport      sport (tennis | futsal)
  grade      text
  is_primary boolean
  created_at timestamptz
  PK (user_id, sport)
)
```

종목 전용 프로필(play_style, ntrp 등)은 불필요 — 테니스/풋살 공용이어야 하므로.

## Layer 1: user_tennis_orgs — 🔶 검토 중

### 현재 구조
```sql
user_tennis_orgs (
  user_id        uuid FK
  org            tennis_org
  division_local text          -- '골드부' 등
  score          numeric(3,1)  -- 0~10
  expires_at     date
  is_primary     boolean
  region_code    text FK
  created_at     timestamptz
  updated_at     timestamptz
  PK (user_id, org)
)
```

### 리서치 대조 — 빠진 항목 3개

1. **grade_level text** — KATO 그룹(MA/A/1/2/3/4) 또는 광주 급수(1.0~6.0)
   - 현재 score와 division_local에 혼재됨
   - score는 협회마다 의미가 다름 (광주=급수, KTA=합산점수, 제주=개인점수, KATA=랭킹포인트)

2. **ranking_points int** — KATA 베스트15 누적 포인트
   - score(0~10)로는 수백~수천 단위 포인트 저장 불가

3. **is_player_origin boolean** — 선수 출신 여부
   - 광주 등급 체계에서 참가 자격이 완전히 달라짐

### 미결 질문
- 이 3개 컬럼을 추가할지, 아니면 오버킬인지 사용자 결정 대기 중

## 클럽 기능 — 이전 브레인스토밍 확정 사항

| 항목 | 결정 |
|------|------|
| 역할 체계 | owner / manager / member (3단계 + 권한 boolean 컬럼) |
| 권한 저장 | club_members에 can_kick, can_create_event, can_post |
| 멀티 가입 | 무제한 |
| 게시판 | 태그 고정 프리셋 (notice, free, recruit, photo), 시간순 |
| 게시판 공지 | notice 태그는 운영자만 작성 |
| 댓글 | 1단, 멘션으로 대상 지정 |
| 알림 6종 | 공지 + 일정등록 + 멘션 + 댓글 + D-1 리마인더 + 참석변경 |
| 일정 등록 | 운영자만 (casual 타입 제거) |
| 채팅 | Post-MVP (게시판 + 카카오 오픈채팅 링크) |
| 캘린더 연동 | ICS 파일 다운로드 |

## 전체 설계 범위 (3개 도메인)

### 1. 클럽 (기존 확장)
멀티 가입, 역할 체계, 게시판, 일정, 알림

### 2. 친구 일정 (신규)
- 대회 파트너/팀원 간 일정 공유
- 서로 수락한 관계(친구)끼리 캘린더 통합
- 클럽 대항전은 클럽 운영진 생성 → 자동 포함
- 구글/아이폰 캘린더 연동 (ICS)

### 3. 경기 이력 + 랭킹 (핵심 차별화)
- 대회 출전 기록, 스코어, 진출 단계
- 협회별 포인트 수집/저장
- 상대 전적 조회
- 지역/협회 간 포인트 통합 → 등급 조작 방지
- 챗봇/메뉴에서 랭킹·포인트 조회
