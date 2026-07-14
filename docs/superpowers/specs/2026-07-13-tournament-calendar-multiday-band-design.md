# 월 캘린더 멀티데이 대회 범위 밴드 — 설계 스펙

- 날짜: 2026-07-13
- 대상 파일: `app/lib/screens/tournaments/tournaments_screen.dart` (파일 1개)
- 테스트: `app/test/` 에 단위 테스트 1개 추가
- 상태: 사용자 합의 완료 설계의 구현 스펙 (새 발명 없음)

## 1. 개요 / 목표

대회 탭 월 캘린더에서 여러 날에 걸친 대회(멀티데이)를 **날짜 원 뒤 연속 배경 띠(밴드)** 로
이어 보이게 한다. 지금은 날짜마다 카운트 배지만 있어 "7/15 배지, 7/16 배지, 7/17 배지"가
같은 대회 하나인지 대회 셋인지 구분되지 않는다. 밴드가 붙으면 연속 구간이 하나의 대회로
읽힌다.

역할 분리:
- **배지(숫자)** = 그날 걸친 대회 수 (기존 그대로 유지)
- **밴드(띠)** = "이 날짜에 2일 이상짜리 대회가 걸쳐 있음" (신규)

## 2. 현재 동작

`_TournamentMonthCalendar` (573~698줄):
- 월 그리드를 `for (var row = 0; row < rowCount; row++)` 로 주(week)마다 `Row` 생성.
- 각 `Row` 는 `List.generate(7, ...)` 로 7개의 `Expanded(_CalendarDayCell)` 를 만든다.
- 셀 날짜는 `_dateForCell(focusedMonth, leadingEmptyCells, row * 7 + col)` — 월 범위 밖이면
  `null` 을 반환하고, 셀은 `count: _tournamentCountOnDate(cellDate, tournaments)` 를 받는다.

`_CalendarDayCell` (726~823줄):
- `date == null` 이면 `SizedBox(height: 46)` 만 반환 (빈 셀).
- 구조: `InkWell > SizedBox(height: 46) > Center > SizedBox.square(dimension: 40) > Stack`.
  Stack 안에 (1) 날짜 원 `AnimatedContainer` (선택 시 `cs.primary` solid 원 34px, 평소 30px,
  오늘은 primary 테두리), (2) `count > 0` 이면 우상단 `Positioned` 카운트 배지.

헬퍼 (890~935줄):
- `_dateOnly`, `_isSameDay`
- `_isDateInTournament(date, tournament)` — `startDate`~`endDate ?? startDate` 포함 판정.
- `_tournamentCountOnDate(date?, tournaments)` — null 이면 0, 아니면 걸친 대회 수.
- `Tournament` 모델: `startDate`(DateTime), `endDate`(DateTime?, null 이면 하루짜리).

## 3. 변경 설계

### 3.1 밴드 표시 조건

- 대회 기간이 **2일 이상** (`endDate != null && _dateOnly(endDate) > _dateOnly(startDate)`)
  인 대회가 그 날짜에 걸쳐 있으면 밴드를 그린다.
- 하루짜리 대회(`endDate == null` 또는 start == end)는 기존처럼 배지만. 밴드 없음.

### 3.2 밴드 시각 스타일

- 은은한 primary 톤 배경 띠. **`colorScheme` 토큰만 사용** — 예:
  `cs.primary.withValues(alpha: ...)` (저알파) 또는 `cs.primaryContainer` 계열.
  `Colors.white` 등 하드코딩 금지 (이 프로젝트는 다크모드 대응 토큰만 쓴다 — 같은 파일
  611줄 주석과 동일 원칙, 다크/라이트 모두 자연스러워야 함).
- 밴드는 **셀 폭을 꽉 채운다(edge-to-edge)**. 각 셀이 `Expanded` 라 인접 셀 밴드와
  맞닿아 자연스럽게 한 줄로 이어진다. 좌우 패딩·마진 금지.
- 모서리:
  - 연속 구간의 **시작 셀** → 왼쪽 모서리만 둥글게
  - **끝 셀** → 오른쪽 모서리만 둥글게
  - **중간 셀** → 양쪽 각지게 (`Radius.zero`)
  - `BorderRadius.horizontal(left: ..., right: ...)` 로 표현.
- 레이어 순서: 밴드는 날짜 원 **뒤(맨 아래)**. 선택된 날짜의 solid primary 원과 겹쳐도
  밴드가 원 좌우로 보인다.

### 3.3 시작/끝 판정 규칙 (Row 단위)

둥근 모서리 판정은 **같은 Row(주) 안에서 인접 셀만** 비교한다:

- `hasBand` = 이 셀 날짜에 멀티데이 대회가 걸쳐 있음 (`_multiDayBandOnDate` 참조)
- `isBandStart` = `hasBand` AND (같은 Row 왼쪽 셀에 밴드 없음 **또는** 왼쪽 셀이 null/없음)
- `isBandEnd` = `hasBand` AND (같은 Row 오른쪽 셀에 밴드 없음 **또는** 오른쪽 셀이 null/없음)

이 규칙 덕에 주간 경계(토→일)는 자동 처리된다: 각 주가 별도 Row 이므로 토요일(col 6)은
오른쪽 셀이 없어 `isBandEnd = true` (오른쪽 둥글게), 다음 주 일요일(col 0)은 왼쪽 셀이
없어 `isBandStart = true` (왼쪽 둥글게). 별도 날짜 연산 불필요.

## 4. 겹침 처리 (단순 유지)

여러 멀티데이 대회가 같은 날짜에 겹쳐도 **밴드는 1줄만** 그린다. 밴드는 "멀티데이 대회가
여기 걸쳐 있다"는 불리언 표현일 뿐이다. 정확히 몇 개인지는 배지 숫자로, 어느 대회인지는
날짜 탭 시 하단 카드 목록으로 확인한다. 대회별 밴드 분리·색 구분·다단 스택은 하지 않는다.

부수 효과(의도된 단순화): 대회 A가 7/15~16, 대회 B가 7/16~17이면 7/15~17이 한 줄 밴드로
이어져 보인다. 허용한다 — 밴드의 의미는 "대회 경계"가 아니라 "멀티데이 걸침 여부"다.

## 5. 구현 위치 (함수/클래스별 변경점)

### 5.1 순수 함수 (파일 하단 헬퍼 구역, `_tournamentCountOnDate` 근처)

```dart
/// 그 날짜에 2일 이상짜리 대회가 걸쳐 있으면 true. (테스트를 위해 public)
@visibleForTesting
bool multiDayBandOnDate(DateTime? date, List<Tournament> tournaments) {
  if (date == null) return false;
  return tournaments.any((t) =>
      t.endDate != null &&
      _dateOnly(t.endDate!).isAfter(_dateOnly(t.startDate)) &&
      _isDateInTournament(date, t));
}
```

- 기존 `_isDateInTournament` 재사용 + 멀티데이 조건만 추가.
- 시그니처를 `DateTime?` 로 받아 null 셀도 `false` 로 흡수 → 호출부의 인접 셀(null 포함)
  비교가 단순해진다.
- **명명 주의**: 합의안 명칭은 `_multiDayBandOnDate` 이나, Dart 의 `_` 접두 함수는
  라이브러리 프라이빗이라 `app/test/` 에서 import 불가. 검증 요구(단위 테스트)를 위해
  **underscore 없이 public + `@visibleForTesting`** 으로 둔다 (기존 테스트들도 public
  심볼 import 방식: `package:allround/...`). 시작/끝 판정도 같은 이유로 아래 5.2 의
  순수 함수로 추출한다.

```dart
/// 한 주(7칸, null = 빈 셀) 날짜 배열에 대해 셀별 (hasBand, isBandStart, isBandEnd) 계산.
@visibleForTesting
List<({bool hasBand, bool isBandStart, bool isBandEnd})> bandFlagsForWeek(
  List<DateTime?> weekDates,
  List<Tournament> tournaments,
)
```

- 구현: 각 셀의 `hasBand` 를 `multiDayBandOnDate` 로 구한 뒤, `isBandStart` =
  `hasBand && (i == 0 || !hasBand[i - 1])`, `isBandEnd` =
  `hasBand && (i == 6 || !hasBand[i + 1])`. null 셀은 `hasBand == false` 이므로
  "왼쪽/오른쪽이 null" 케이스가 자동 포함된다.
- record 타입 대신 작은 클래스로 해도 무방 — 파일 내 기존 스타일을 따르되 최소로.

### 5.2 `_TournamentMonthCalendar.build` (668~686줄 주 루프)

- 주 루프에서 먼저 `weekDates` (`List<DateTime?>` 7개) 를 만들고
  `bandFlagsForWeek(weekDates, tournaments)` 를 한 번 호출.
- 각 `_CalendarDayCell` 에 `hasBand` / `isBandStart` / `isBandEnd` 를 전달.
- `count` 계산 등 기존 로직은 그대로.

### 5.3 `_CalendarDayCell`

- 파라미터 3개 추가: `final bool hasBand;`, `final bool isBandStart;`,
  `final bool isBandEnd;` (모두 required).
- 위젯 구조 변경 — **주의**: 기존 `Stack` 은 `Center > SizedBox.square(40)` 안에 있어
  폭이 40px 뿐이다. 밴드를 edge-to-edge 로 그리려면 밴드 레이어는 40px 정사각형 **바깥**,
  셀 전체 폭 레벨에 있어야 한다. 즉:

```
InkWell
└─ SizedBox(height: 46)
   └─ Stack(alignment: Alignment.center)      // 신규 외곽 Stack
      ├─ if (hasBand)                          // 맨 아래 레이어, 셀 전체 폭
      │    Container(
      │      height: <밴드 높이, 날짜 원(30)과 어울리는 값>,
      │      width: double.infinity,           // edge-to-edge
      │      decoration: BoxDecoration(
      │        color: <primary 저알파 토큰>,
      │        borderRadius: BorderRadius.horizontal(
      │          left: isBandStart ? Radius.circular(...) : Radius.zero,
      │          right: isBandEnd ? Radius.circular(...) : Radius.zero,
      │        ),
      │      ),
      │    )
      └─ Center > SizedBox.square(40) > Stack( 기존 날짜 원 + 배지 )  // 그대로
```

- `date == null` 빈 셀 분기(`SizedBox(height: 46)`)는 그대로 — 빈 셀엔 밴드 없음
  (호출부에서 이미 `hasBand == false`).
- 카운트 배지, 선택 원, 오늘 테두리 로직은 변경하지 않는다.
- 참고: `InkWell` 의 `borderRadius: BorderRadius.circular(12)` 리플이 밴드 위에 그려지는
  것은 기존 동작 유지 차원에서 그대로 둔다.

## 6. 엣지 케이스

| 케이스 | 기대 동작 |
|---|---|
| 주간 경계 (대회 토~다음 주 월) | 첫 주 토요일: 오른쪽 둥글게(`isBandEnd`, Row 끝). 다음 주 일요일: 왼쪽 둥글게(`isBandStart`, Row 시작). 밴드가 줄 바꿈으로 자연스럽게 끊겼다 이어진다. |
| 월 경계 (대회가 다음 달까지) | 이번 달 마지막 날까지 밴드, 마지막 날이 Row 중간이면 그 오른쪽 셀은 null → `isBandEnd = true` 로 오른쪽 둥글게. 다음 달로 넘기면 1일부터 밴드 이어짐 (왼쪽 null → `isBandStart`). 월 밖 날짜는 셀 자체가 null 이라 밴드 없음. |
| 하루짜리 대회 | `endDate == null` 또는 start == end → 밴드 없음, 배지만 (기존과 동일). |
| 선택된 날짜와 겹침 | 밴드가 solid primary 원 **뒤** 레이어라 원 좌우로 밴드가 보인다. 원/배지 스타일 변경 없음. |
| 시작=끝이 같은 주 하루만 걸침 (예: 밴드 구간의 일요일 하루) | `isBandStart && isBandEnd` 동시 true → 양쪽 둥근 알약 모양. |
| 멀티데이 대회 여러 개 겹침/인접 | 밴드 1줄로 합쳐 보임 (4장 참조, 의도된 동작). |
| 빈 셀(월 앞뒤 여백) | `date == null` → `hasBand false`, 렌더링 변화 없음. |

## 7. 검증 방법

`app/test/tournament_calendar_band_test.dart` 1개. flutter_test 의 `test()` 만 사용,
위젯 테스트·픽스처 없이 순수 함수만 검증한다. `package:allround/screens/tournaments/tournaments_screen.dart`
에서 `multiDayBandOnDate`, `bandFlagsForWeek` import.

테스트 케이스 (최소):

1. **`multiDayBandOnDate` 기본**
   - 7/15~7/19 대회: 7/14 → false, 7/15 → true, 7/17 → true, 7/19 → true, 7/20 → false.
   - 하루짜리 (7/16, endDate null): 7/16 → false.
   - start == end (endDate == startDate): false.
   - date null → false.

2. **`bandFlagsForWeek` 주 중간 구간** — 7/15(수)~7/19(일)… *예시는 2026-07 실제 요일과
   무관하게* 주 배열 `[7/13, 7/14, 7/15, 7/16, 7/17, 7/18, 7/19]` + 7/15~7/19 대회:
   - index 0,1: hasBand false
   - index 2: hasBand true, isBandStart true, isBandEnd false
   - index 3~5: hasBand true, start/end 모두 false
   - index 6: hasBand true, isBandStart false, isBandEnd true (Row 끝)

3. **주간 경계 (토~다음 주 월)** — 대회 7/18(토)~7/20(월) 가정:
   - 첫 주 배열 `[..., 7/17, 7/18]`: 7/18 셀 → isBandStart true **그리고** isBandEnd true
     (왼쪽 밴드 없음 + Row 마지막).
   - 다음 주 배열 `[7/19, 7/20, 7/21, ...]`: 7/19 → start true / end false,
     7/20 → start false / end true, 7/21 → hasBand false.

4. **null 셀 경계 (월 첫 주)** — 주 배열 `[null, null, 7/1, 7/2, ...]` + 6/30~7/2 대회:
   - 7/1 → hasBand true, isBandStart true (왼쪽이 null), 7/2 → isBandEnd true.

실행: `cd app && flutter test test/tournament_calendar_band_test.dart`.
그 외 기존 검증: `flutter analyze` 통과.

## 8. 안 하는 것 (YAGNI)

- 대회별 색상 구분
- 간트식 다단 밴드 스택 (겹침 시 여러 줄)
- 하루짜리 대회 밴드
- 밴드 탭 인터랙션 (탭은 기존 날짜 셀 탭 그대로)
- 애니메이션 (선택 원 애니메이션은 기존 것만 유지)
