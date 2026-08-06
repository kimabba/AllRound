/// 대회 리스트 카드(TournamentCard)가 보여주는 3가지 정보 — 대회일/기간,
/// 신청 마감, 위치 — 의 표시 텍스트를 만드는 순수 로직.
///
/// 위젯을 public 화하지 않고도 규칙을 단위 테스트할 수 있도록 순수 함수로
/// 분리한다. 날짜 포맷은 호출부(위젯)에서 주입해 intl 로케일 초기화 의존을
/// 테스트에서 격리한다.
library;

/// 신청 마감일 기준 상태.
enum DeadlineStatus {
  /// 마감일 미정(applicationDeadline == null).
  none,

  /// 마감일이 지남(daysLeft < 0).
  passed,

  /// 오늘이 마감일(daysLeft == 0).
  today,

  /// 마감 임박(1~7일 남음) — D-day 배지 노출 구간.
  soon,

  /// 여유 있음(8일 이상 남음).
  open,
}

/// [deadline] 과 [today] 로 마감 상태와 남은 일수를 계산한다.
/// [today] 는 날짜만 비교하므로 시각 성분은 무시한다.
class DeadlineInfo {
  const DeadlineInfo({required this.status, required this.daysLeft});

  final DeadlineStatus status;

  /// 남은 일수. status == none 이면 null.
  final int? daysLeft;

  static DeadlineInfo compute(DateTime? deadline, DateTime today) {
    if (deadline == null) {
      return const DeadlineInfo(status: DeadlineStatus.none, daysLeft: null);
    }
    final todayDate = DateTime(today.year, today.month, today.day);
    final deadlineDate =
        DateTime(deadline.year, deadline.month, deadline.day);
    final daysLeft = deadlineDate.difference(todayDate).inDays;
    final DeadlineStatus status;
    if (daysLeft < 0) {
      status = DeadlineStatus.passed;
    } else if (daysLeft == 0) {
      status = DeadlineStatus.today;
    } else if (daysLeft <= 7) {
      status = DeadlineStatus.soon;
    } else {
      status = DeadlineStatus.open;
    }
    return DeadlineInfo(status: status, daysLeft: daysLeft);
  }

  /// D-day 배지 텍스트. 1~7일 남았을 때만 노출('D-Day'/'D-N'), 그 외 빈 문자열.
  String get ddayBadge {
    switch (status) {
      case DeadlineStatus.today:
        return 'D-Day';
      case DeadlineStatus.soon:
        return 'D-$daysLeft';
      case DeadlineStatus.none:
      case DeadlineStatus.passed:
      case DeadlineStatus.open:
        return '';
    }
  }
}

/// 두 날짜가 같은 날인지(연/월/일) 판정.
bool isSameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// 대회일/기간 라벨 뒤에 붙는 날짜 텍스트.
/// 단일일이면 "M/d (E)", 다중일이면 "시작~종료".
/// [format] 은 DateFormat('M/d (E)','ko').format 같은 포매터를 주입.
String tournamentDateText(
  DateTime startDate,
  DateTime? endDate,
  String Function(DateTime) format,
) {
  final start = format(startDate);
  if (endDate == null || isSameCalendarDay(startDate, endDate)) return start;
  return '$start~${format(endDate)}';
}

/// 신청 마감 텍스트. "~M/D 마감" 형태. 마감일 미정이면 빈 문자열.
/// 마감이 지났어도 마감일 자체는 정보로 유용하므로 텍스트는 항상 만든다
/// (상태 배지가 '마감'을 별도로 알린다).
String applicationDeadlineText(
  DateTime? deadline,
  String Function(DateTime) format,
) {
  if (deadline == null) return '';
  return '~${format(deadline)} 마감';
}

/// 위치 텍스트. location 우선, null 이면 region 폴백.
/// 둘 다 있으면 "location · region" 로 함께 보여 구체 장소와 지역을 모두 노출.
/// 둘 다 null/빈 값이면 빈 문자열.
String locationText(String? location, String? region) {
  final loc = location?.trim();
  final reg = region?.trim();
  final hasLoc = loc != null && loc.isNotEmpty;
  final hasReg = reg != null && reg.isNotEmpty;
  if (hasLoc && hasReg && loc != reg) return '$loc · $reg';
  if (hasLoc) return loc;
  if (hasReg) return reg;
  return '';
}
