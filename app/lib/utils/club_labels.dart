String clubGenderCode(String? value) {
  switch (value?.trim().toLowerCase()) {
    case 'mixed':
    case 'mix':
    case '혼성':
      return 'mixed';
    case 'male':
    case 'men':
    case '남성':
    case '남자':
      return 'male';
    case 'female':
    case 'women':
    case '여성':
    case '여자':
      return 'female';
    default:
      return '';
  }
}

String clubGenderLabel(String? value) {
  switch (clubGenderCode(value)) {
    case 'mixed':
      return '혼성';
    case 'male':
      return '남성';
    case 'female':
      return '여성';
    default:
      return value?.trim() ?? '';
  }
}

bool clubGenderMatches(String? clubValue, String filterValue) {
  final filterCode = clubGenderCode(filterValue);
  if (filterCode.isEmpty) return true;
  final clubCode = clubGenderCode(clubValue);
  if (clubCode.isEmpty) return true;
  return clubCode == filterCode;
}

String clubDayCode(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  final short = trimmed.replaceAll('요일', '');
  return short.isEmpty ? '' : short.substring(0, 1);
}

bool clubDaysMatch(List<String> clubDays, Set<String> filterDays) {
  if (filterDays.isEmpty || clubDays.isEmpty) return true;
  final normalizedFilters = filterDays.map(clubDayCode).toSet();
  return clubDays.map(clubDayCode).any(normalizedFilters.contains);
}

bool clubRegionMatches(String? clubRegion, String filterRegion) {
  final club = clubRegion?.trim();
  final filter = filterRegion.trim();
  if (filter.isEmpty || club == null || club.isEmpty) return true;
  return club == filter || club.startsWith(filter) || filter.startsWith(club);
}

bool clubNameMatchesQuery(String clubName, String query) {
  final tokens = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .toList();
  if (tokens.isEmpty) return true;

  final name = clubName.toLowerCase();
  final compactName = name.replaceAll(RegExp(r'\s+'), '');
  final compactQuery = tokens.join();
  if (compactName.contains(compactQuery)) return true;

  return tokens.every(name.contains);
}

String clubMonthlyFeeLabel(int fee) {
  if (fee <= 0) return '월회비 무료';
  if (fee % 10000 == 0) return '월회비 ${fee ~/ 10000}만원';
  if (fee % 1000 == 0) return '월회비 ${fee ~/ 1000}천원';
  return '월회비 $fee원';
}
