# 스키마 감사 — 남은 결정 사항 (2026-06-17)

P0/P1/P2(안전분)/P3(storage)는 마이그레이션으로 해소됨(064~069). 아래는 **데이터 모델 결정이 필요하거나 의도적 트레이드오프**라 코드 즉시 수정 대신 기록만 함.

## 1. futsal 메타 완전성 (P2, 059 배치 잔재)

**현상**: 059에서 `tournaments` 확장 컬럼을 분리할 때:
- `division_gender`, `division_age_group` → `tennis_tournament_details` 에 배치 (futsal 도 쓸 수 있는 값인데 tennis 쪽에만 존재)
- `team_count_current` → details 어디에도 안 옮기고 DROP (소실)

**영향**: `tournaments_for_user`(064)에서 futsal 대회는 `fd` 로만 JOIN 되므로 위 값들이 NULL 로 반환. 단 현재 futsal 대회 1건이라 실영향 미미.

**결정 필요**:
- (A) `division_gender`/`division_age_group` 이 종목 공용이면 → 두 details 테이블에 각각 두거나, `tournaments` 공통으로 환원
- (B) `team_count_current` 가 슬롯 표시에 필요하면 → `futsal_tournament_details` 에 컬럼 추가 + 064 RPC 에서 `fd` 선택

→ futsal 대회 운영이 본격화되기 전 결정 권장. 지금은 긴급도 낮음.

## 2. auth.users vs public.users FK target 통일 (P1 보류분)

067에서 ON DELETE 정책은 정합화했으나 **target 통일은 보류**.
- 구 클럽 테이블 일부가 `auth.users` 직접 참조, 신규는 `public.users` 참조.
- 통일 시 위험: `public.users` 는 auth 삭제 시 cascade되므로 연쇄 삭제 범위가 바뀜. `auth` 에는 있고 `public` 프로필이 없는 ID 가 있으면 FK 추가 실패.
- 권장: `public.users` backfill 검증 → `ADD CONSTRAINT ... NOT VALID` → `VALIDATE CONSTRAINT` (락 최소화). 데이터 정합 확인이 선행되어야 함.

## 3. region 비정규화 캐시 (P3, 트레이드오프)

`tournaments.region`(한글) + `region_code`(FK regions) 병존. 표시 편의용 캐시.
- 위험: 쓰기 경로에서 둘이 어긋날 수 있음(051 backfill 이력).
- 권장(선택): 쓰기 시 서버에서 `region_code` 보정 또는 트리거로 drift 감지. 현재 크롤러는 `regionCodeFromLabel` 로 보정 중.

## 4. venues 미연결 (P3, 트레이드오프)

`venues`(269건) 마스터가 있으나 `tournaments.location` / `club_events.location_text` 는 자유 text, FK 없음.
- 의도적 느슨함(크롤 데이터는 정형 장소 매칭이 어려움).
- 권장(선택): nullable `venue_id` 를 점진 도입해 매칭되는 건만 연결. 강제 FK 는 비권장.

## 5. 폴리모픽 FK (P3, 트레이드오프)

`schedule_shares.event_id`(event_type 별), `notifications.reference_id`(reference_type 별) 는 FK 없음 → 고아 가능.
- 의도적(여러 대상 가리킴). 무결성은 앱/RPC 책임.
- 권장(선택): `reference_type` 별 검증 트리거 또는 정리 잡. 긴급도 낮음.
