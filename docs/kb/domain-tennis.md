# 테니스 도메인 지식

## 협회 체계 (tennis_org)

| 코드 | 협회명 | 등급 특성 |
|---|---|---|
| gj | 광주광역시 테니스협회 | 오픈/골드/일반/신인/지도자/마스터즈 등 |
| jn | 전남 테니스협회 | 광주와 유사하나 별도 등급 체계 |
| kta | 대한테니스협회 | 1~6부 숫자 등급 |
| kata | 한국아마추어테니스협회 | S/A/B/C/D 등급 |
| ktfs | 대한테니스지도자연맹 | 지도자 전용 |
| kstf | 대한소프트테니스연맹 | 소프트테니스 |
| local | 지역 자체 | 대회별 자체 부서 |

## 부서코드 체계 (division code)

형식: `{org}_{gender}_{type}` 또는 `{org}_{number}`

### 광주 (gj) / 전남 (jn) 예시
```
gj_m_open      오픈부 (남)
gj_m_gold      골드부 (남)
gj_m_general   일반부 (남)
gj_m_rookie    신인부 (남)
gj_m_instructor 지도자부 (남)
gj_m_masters   마스터즈부 (남)
gj_w_open      오픈부 (여)
gj_w_general   일반부 (여)
gj_mx_mixed    혼합복식
```

### KTA 예시
```
kta_1 ~ kta_6  1부 ~ 6부
```

### KATA 예시
```
kata_s, kata_a, kata_b, kata_c, kata_d
```

## 코드 정의 위치

- **Backend:** `supabase/functions/_shared/enums.ts` → `TENNIS_DIVISIONS` 배열 (60+ 항목)
- **Flutter:** `app/lib/utils/grade_labels.dart` → `tennisDivisions` (1:1 동기화)

## 크롤러 부서 추출

`extractSidoStdDivisions(text, org)` — 대회 요강 텍스트에서 부서명 매칭:
- `GJ_KEYWORD_TO_SUFFIX` 키워드 매핑 사용
- 예: "골드부 · 일반부" → `['gj_m_gold', 'gj_m_general']`
- 매칭 없으면 기본값: `m_open + m_general`
- 결과는 `eligible_grades` 배열 + `division_label_local` 텍스트로 저장

## tournaments 테이블 관련 컬럼
- `eligible_grades: text[]` — 부서코드 배열
- `division_label_local: text` — 크롤러 원본 부서명 (UI 우선 표시)
- `host_orgs: tennis_org[]` — 주최 협회
- `host_associations: text[]` — 주최 단체명

## 사용자 등급 등록
- `user_tennis_orgs` 테이블에 협회별 등급 개별 등록
- 한 사용자가 여러 협회 등급 보유 가능 (예: 광주 골드 + KTA 3부)
- `is_primary` 플래그로 주 협회 지정
