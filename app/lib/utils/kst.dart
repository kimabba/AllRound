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
