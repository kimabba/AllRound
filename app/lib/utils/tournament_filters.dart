/// 상세검색 시트의 앱 전용(클라이언트 측) 필터 순수 로직.
///
/// 백엔드 비의존 — 기간 프리셋 범위 계산과 모집 상태 판정만 담당한다.
/// UI 위젯과 분리해 단위 테스트가 가능하도록 했다.
library;

/// 기간 프리셋. `custom` 은 사용자가 showDateRangePicker 로 직접 고른 범위,
/// `all` 은 기간 필터 해제(전체)를 의미한다.
enum DatePreset { all, thisMonth, nextMonth, thisYear, custom }

/// 프리셋 칩 표시 라벨.
String datePresetLabel(DatePreset preset) {
  switch (preset) {
    case DatePreset.all:
      return '전체';
    case DatePreset.thisMonth:
      return '당월';
    case DatePreset.nextMonth:
      return '익월';
    case DatePreset.thisYear:
      return '올해';
    case DatePreset.custom:
      return '직접선택';
  }
}

/// 날짜만 비교하기 위한 정규화(시·분·초 제거).
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// 프리셋 → (dateFrom, dateTo) 날짜 범위.
///
/// - all: (null, null) — 기간 필터 해제
/// - thisMonth: 이번 달 1일 ~ 말일
/// - nextMonth: 다음 달 1일 ~ 말일
/// - thisYear: 올해 1/1 ~ 12/31
/// - custom: (null, null) — 직접선택은 호출자가 picker 결과로 채운다
///
/// 반환은 record `(DateTime? from, DateTime? to)`.
(DateTime?, DateTime?) dateRangeForPreset(DatePreset preset, DateTime now) {
  final y = now.year;
  final m = now.month;
  switch (preset) {
    case DatePreset.all:
    case DatePreset.custom:
      return (null, null);
    case DatePreset.thisMonth:
      // 말일: 다음 달 0일 = 이번 달 마지막 날
      return (DateTime(y, m, 1), DateTime(y, m + 1, 0));
    case DatePreset.nextMonth:
      return (DateTime(y, m + 1, 1), DateTime(y, m + 2, 0));
    case DatePreset.thisYear:
      return (DateTime(y, 1, 1), DateTime(y, 12, 31));
  }
}

/// 현재 (dateFrom, dateTo) 가 어떤 프리셋과 일치하는지 역추론한다.
/// 일치하는 표준 프리셋이 없으면:
/// - 둘 다 null → all
/// - 그 외(직접 고른 범위) → custom
DatePreset presetForRange(DateTime? from, DateTime? to, DateTime now) {
  if (from == null && to == null) return DatePreset.all;
  for (final preset in const [
    DatePreset.thisMonth,
    DatePreset.nextMonth,
    DatePreset.thisYear,
  ]) {
    final (pf, pt) = dateRangeForPreset(preset, now);
    if (pf != null &&
        pt != null &&
        from != null &&
        to != null &&
        dateOnly(from) == dateOnly(pf) &&
        dateOnly(to) == dateOnly(pt)) {
      return preset;
    }
  }
  return DatePreset.custom;
}

/// 모집 상태 필터. `all` 은 필터 없음.
enum RecruitingStatus { all, recruiting, closed }

/// 모집 상태 칩 표시 라벨.
String recruitingStatusLabel(RecruitingStatus status) {
  switch (status) {
    case RecruitingStatus.all:
      return '전체';
    case RecruitingStatus.recruiting:
      return '모집중';
    case RecruitingStatus.closed:
      return '마감';
  }
}

/// 모집 상태 → 서버 쿼리 파라미터(`recruiting` 키) 값.
///
/// 서버(tournaments-search → tournaments_for_user)가 application_deadline
/// 기준으로 필터한다. all 은 필터 없음(null).
/// - recruiting → 'open'
/// - closed → 'closed'
/// - all → null
String? recruitingStatusToParam(RecruitingStatus status) {
  switch (status) {
    case RecruitingStatus.all:
      return null;
    case RecruitingStatus.recruiting:
      return 'open';
    case RecruitingStatus.closed:
      return 'closed';
  }
}
