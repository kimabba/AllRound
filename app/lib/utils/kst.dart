/// KST(Asia/Seoul) 기준 오늘 날짜, 'YYYY-MM-DD'.
///
/// **기기 로컬이 아니라 KST 로 고정한다** — 서버의 자동 마감
/// (`_shared/tournament_status.ts` `syncTournamentStatus`)과 대회 일정 판정이
/// KST 로 이뤄지므로, 기기 시간대를 쓰면 KST 보다 앞선 곳(예: 시드니)에서
/// 한국 자정 전에 오늘자 대회가 지난 것으로 보인다.
///
/// `date` 컬럼(start_date/end_date)과 비교할 때는 ISO 문자열끼리 사전순 비교가
/// 곧 시간순 비교라 파싱 없이 바로 쓴다.
String kstToday(DateTime now) {
  final kst = now.toUtc().add(const Duration(hours: 9));
  return '${kst.year.toString().padLeft(4, '0')}-'
      '${kst.month.toString().padLeft(2, '0')}-'
      '${kst.day.toString().padLeft(2, '0')}';
}

/// KST 기준 오늘 자정 — `DateTime` 끼리 날짜 차이를 셀 때 쓴다(D-day, 마감 판정).
///
/// `DateTime(now.year, now.month, now.day)` 는 **기기 로컬** 자정이라 쓰지 않는다.
/// 서버가 KST 로 마감을 판정하므로(tournaments_for_user 등 `p_recruiting` 필터),
/// 기기 시간대를 따라가면 한국 자정 근처에서 앱이 하루 먼저 '마감'을 띄운다.
///
/// 반환값은 **KST 벽시계 날짜를 담은 로컬 DateTime** 이다. 시각 성분이 0 이라
/// `applicationDeadline`(날짜만 있는 값)과의 `difference(...).inDays` 가
/// 시간대와 무관하게 정확한 일수를 준다.
DateTime kstTodayDate(DateTime now) {
  final kst = now.toUtc().add(const Duration(hours: 9));
  return DateTime(kst.year, kst.month, kst.day);
}

/// `now`를 KST 벽시계 시각을 담은(시각 성분 포함) 로컬 `DateTime`으로 바꾼다.
/// 연도 경계처럼 날짜뿐 아니라 시각까지 KST 기준으로 비교해야 할 때 쓴다.
DateTime kstNow(DateTime now) => now.toUtc().add(const Duration(hours: 9));
