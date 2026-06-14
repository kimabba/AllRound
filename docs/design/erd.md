# Match-up ERD (Entity Relationship Diagram)

> VS Code에서 `Cmd+Shift+V`로 미리보기. 설계 진행하면서 계속 업데이트.

## 전체 ERD

```mermaid
erDiagram
    %% ===== Layer 0: 사용자 =====
    users {
        uuid id PK
        text email
        text name "실명"
        text nickname "닉네임"
        text avatar_url "프로필 사진"
        text phone "연락처"
        int birth_year "출생 연도"
        text gender "male or female"
        text bio "자기소개"
        text primary_region FK "주 활동 지역"
        text_arr interest_regions "관심 지역 max 3"
        text role "user or admin"
        timestamptz created_at
        timestamptz updated_at
    }

    %% ===== Layer 1: 종목/협회 =====
    user_sports {
        uuid user_id FK
        text sport "tennis or futsal"
        text grade
        boolean is_primary
    }

    user_tennis_orgs {
        uuid user_id FK
        text org "kta gj kato kata..."
        text division "골드부 오픈부 등 - PK"
        numeric score "등급 점수 통합"
        int ranking_points "누적 포인트"
        text player_origin "선수출신 단계"
        boolean is_primary
        text region_code FK
    }

    %% ===== Layer 2: 대회 (공통+확장) =====
    tournaments {
        uuid id PK
        text sport
        text title
        text organizer
        text description
        date start_date
        text region_code FK
        text status "draft published closed"
        vector embedding
    }

    tennis_tournament_details {
        uuid tournament_id PK_FK
        text_arr host_orgs
        text division_kta_standard
        text division_gender
        text division_age_group
        boolean is_joint_event
    }

    futsal_tournament_details {
        uuid tournament_id PK_FK
        text venue_type
        text surface_type
        text match_format
        int player_count
        int roster_min
        int roster_max
    }

    tournament_favorites {
        uuid user_id FK
        uuid tournament_id FK
    }

    %% ===== Layer 2: 클럽 =====
    clubs {
        uuid id PK
        text sport
        text name
        text region
        text logo_url
        text_arr meeting_days "NEW 모임요일"
        int monthly_fee "NEW 월회비"
        text gender_preference "NEW male female mixed"
        text status "pending approved rejected"
        int member_count
    }

    club_favorites {
        uuid user_id FK
        uuid club_id FK
    }

    %% ===== Layer 3: 클럽 멤버십 =====
    club_members {
        uuid id PK
        uuid club_id FK
        uuid user_id FK
        text role "owner manager member"
        text status "active left banned"
        boolean can_kick "NEW"
        boolean can_create_event "NEW"
        boolean can_post_notice "NEW"
    }

    club_join_requests {
        uuid id PK
        uuid club_id FK
        uuid user_id FK
        text status "pending approved rejected"
    }

    %% ===== Layer 4: 클럽 일정 =====
    club_events {
        uuid id PK
        uuid club_id FK
        uuid created_by FK
        text title
        timestamptz starts_at
    }

    club_event_attendees {
        uuid id PK
        uuid event_id FK
        uuid user_id FK
        text status "going not_going"
    }

    %% ===== Layer 4: 클럽 게시판 (NEW) =====
    club_posts {
        uuid id PK
        uuid club_id FK
        uuid author_id FK
        text tag "notice free recruit photo"
        text title
        text body
        text_arr image_urls "max 5"
        timestamptz created_at
    }

    club_post_comments {
        uuid id PK
        uuid post_id FK
        uuid author_id FK
        text body
        timestamptz created_at
    }

    club_post_mentions {
        uuid id PK
        uuid post_id FK
        uuid comment_id FK "nullable"
        uuid mentioned_user_id FK
    }

    %% ===== Layer 5: 알림 (통합) =====
    notifications {
        uuid id PK
        uuid user_id FK
        text type "8종"
        text title
        text body
        text reference_type
        uuid reference_id
        uuid club_id "nullable"
        boolean is_read
        text status "pending sent failed"
    }

    device_tokens {
        uuid user_id FK
        text token
        text platform "ios android web"
    }

    %% ===== Layer 6: 경기 이력 (NEW) =====
    match_entries {
        uuid id PK
        uuid user_id FK
        uuid tournament_id FK
        text division "참가 부서"
        uuid partner_id FK "복식 파트너"
        text partner_name "비회원 파트너"
        text team_name "풋살 팀명"
        text final_round "우승 준우승 8강..."
        int points_earned
        text source "manual crawl admin"
    }

    match_rounds {
        uuid id PK
        uuid entry_id FK
        text round "1회전 8강 결승..."
        uuid opponent_1_id FK "nullable"
        text opponent_1_name
        uuid opponent_2_id FK "nullable"
        text opponent_2_name
        text score "6:3"
        text result "win lose"
        date played_at
    }

    %% ===== Layer 7: 일정 공유 (NEW) =====
    schedule_shares {
        uuid id PK
        uuid shared_by FK
        uuid shared_with FK
        text event_type "tournament club_event"
        uuid event_id
        text status "pending accepted declined"
    }

    %% ===== 기존 유지 =====
    chat_messages {
        uuid id PK
        uuid user_id FK
        text conversation_id
        text role
        text content
    }

    rule_articles {
        uuid id PK
        text sport
        text category
        text title
        text body
        vector embedding
    }

    venues {
        uuid id PK
        text name
        text region
        text venue_type
    }

    regions {
        text code PK
        text display_name_ko
    }

    %% ===== 관계선 =====
    users ||--o{ user_sports : "registers"
    users ||--o{ user_tennis_orgs : "belongs to"
    users ||--o{ tournament_favorites : "bookmarks"
    users ||--o{ club_favorites : "bookmarks"
    users ||--o{ club_members : "joins"
    users ||--o{ club_join_requests : "requests"
    users ||--o{ club_posts : "writes"
    users ||--o{ club_post_comments : "writes"
    users ||--o{ chat_messages : "chats"
    users ||--o{ device_tokens : "has"
    users ||--o{ notifications : "receives"
    users ||--o{ club_event_attendees : "responds"
    users ||--o{ match_entries : "participates"
    users ||--o{ schedule_shares : "shares"

    regions ||--o{ users : "primary_region"
    regions ||--o{ user_tennis_orgs : "region_code"

    tournaments ||--o{ tournament_favorites : "bookmarked by"
    tournaments ||--o| tennis_tournament_details : "has"
    tournaments ||--o| futsal_tournament_details : "has"
    tournaments ||--o{ match_entries : "records"

    clubs ||--o{ club_members : "has"
    clubs ||--o{ club_join_requests : "receives"
    clubs ||--o{ club_events : "schedules"
    clubs ||--o{ club_posts : "contains"
    clubs ||--o{ club_favorites : "bookmarked by"

    club_events ||--o{ club_event_attendees : "has"
    club_posts ||--o{ club_post_comments : "has"
    club_posts ||--o{ club_post_mentions : "has"
    club_post_comments ||--o{ club_post_mentions : "has"

    match_entries ||--o{ match_rounds : "has"
```

## 테이블 수 요약

| 구분 | 테이블 | 수 |
|------|--------|---|
| 기존 유지 | users, user_sports, user_tennis_orgs, tournaments, tournament_favorites, clubs, club_favorites, club_members, club_join_requests, club_events, club_event_attendees, device_tokens, regions, venues, chat 관련 4개, 크롤러 2개 | 20 |
| 수정 | users(+8컬럼), clubs(+3컬럼), club_members(+3컬럼), user_tennis_orgs(PK변경), club_events(type제거) | 5 |
| 신규 | tennis_tournament_details, futsal_tournament_details, club_posts, club_post_comments, club_post_mentions, notifications, match_entries, match_rounds, schedule_shares | 9 |
| **합계** | | **29** |
