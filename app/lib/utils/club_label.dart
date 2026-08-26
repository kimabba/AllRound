/// 협회 원문 소속(club_raw)을 표시용 라벨로 다듬는다.
///
/// 원문은 협회 표기 그대로 미러된다(크롤 미러는 원문 보존이 원칙) —
/// '어등산/' 처럼 '/' 구분 뒤에 빈 꼬리가 남거나, '금호/어등산' 처럼
/// 여러 클럽이 붙어 온다. 정리는 표시 계층인 여기서만 한다:
/// '/' 로 나눠 앞뒤 공백과 빈 조각을 버리고 ' · ' 로 잇는다.
///
/// 남는 조각이 없으면(null·빈 문자열·구분자뿐) null — 호출부는 줄 자체를
/// 생략하면 된다.
String? clubLabel(String? clubRaw) {
  if (clubRaw == null) return null;
  final parts = clubRaw
      .split('/')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (parts.isEmpty) return null;
  return parts.join(' · ');
}
