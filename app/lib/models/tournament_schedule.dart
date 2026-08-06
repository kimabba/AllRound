/// 대회 요강 "부서별 일정·장소" 필드 값의 파싱 로직.
///
/// 값은 아래 형태의 줄이 "\n" 으로 이어진 평문이다(요강 AI 정형화 산출물).
///
///     개나리부(서산,태안) · 2026년 08월 07일 (금) 09:00 · 서산시 종합운동장 테니스장
///
/// 한 대회에 12줄까지 들어가는데, `2026년 08월` 과 `09:00` 이 매 줄 반복돼
/// 정작 다른 정보(부서·지역·장소)가 묻힌다. 날짜로 묶어 중복을 걷어내려고
/// 순수 함수로 분리한다(UI 없이 단위 테스트 가능).
///
/// **한 줄이라도 형식에서 벗어나면 전체를 포기하고 빈 리스트를 돌려준다.**
/// 크롤 원문이 바뀌어도 호출부가 평문 렌더로 폴백하면 되므로, 억지로 일부만
/// 해석해서 정보를 잃는 것보다 안전하다.
library;

/// 같은 부서·시간에 묶인 장소 하나.
class SchedulePlace {
  /// 부서명 괄호 안의 지역 표기. `개나리부(서산,태안)` → `서산·태안`.
  /// 괄호가 없으면 null.
  final String? area;

  final String venue;

  const SchedulePlace({required this.venue, this.area});
}

/// 한 날짜 안에서 부서(+시간)로 묶은 그룹.
class ScheduleDivisionGroup {
  /// 괄호를 뗀 부서명. `개나리부(서산,태안)` → `개나리부`.
  final String division;

  final String time;

  final List<SchedulePlace> places;

  const ScheduleDivisionGroup({
    required this.division,
    required this.time,
    required this.places,
  });
}

/// 하루치 일정.
class ScheduleDay {
  final DateTime date;

  /// 원문에 적힌 요일 한 글자(`목`). 원문을 신뢰하고 재계산하지 않는다.
  final String weekday;

  final List<ScheduleDivisionGroup> divisions;

  const ScheduleDay({
    required this.date,
    required this.weekday,
    required this.divisions,
  });
}

// `2026년 08월 07일 (금) 09:00`
final _whenPattern = RegExp(
  r'^(\d{4})년\s*(\d{1,2})월\s*(\d{1,2})일\s*\(([^)]{1,3})\)\s*(\d{1,2}):(\d{2})$',
);

// `개나리부(서산,태안)` → 이름 + 괄호 안
final _divisionPattern = RegExp(r'^(.+?)\s*\(([^)]*)\)\s*$');

const _separator = ' · ';

/// "부서별 일정·장소" 값을 날짜별로 묶어 돌려준다.
/// 형식이 하나라도 어긋나면 빈 리스트(호출부는 평문 폴백).
List<ScheduleDay> parseTournamentSchedule(String value) {
  final lines = value
      .replaceAll('\r\n', '\n')
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList(growable: false);
  if (lines.isEmpty) return const [];

  // 순서 보존이 중요하다(원문이 날짜순으로 온다). LinkedHashMap 기본 동작에 기댄다.
  final days = <String, _DayBuilder>{};

  for (final line in lines) {
    final parts = line.split(_separator);
    // 장소에 ' · ' 가 들어갈 수 있으므로 앞 두 조각만 고정으로 보고 나머지는 되붙인다.
    if (parts.length < 3) return const [];

    final when = _whenPattern.firstMatch(parts[1].trim());
    if (when == null) return const [];

    final venue = parts.sublist(2).join(_separator).trim();
    if (venue.isEmpty) return const [];

    final rawDivision = parts[0].trim();
    if (rawDivision.isEmpty) return const [];

    final year = int.parse(when.group(1)!);
    final month = int.parse(when.group(2)!);
    final day = int.parse(when.group(3)!);
    final weekday = when.group(4)!.trim();
    final time = '${when.group(5)!.padLeft(2, '0')}:${when.group(6)!}';

    final divisionMatch = _divisionPattern.firstMatch(rawDivision);
    final division = divisionMatch == null
        ? rawDivision
        : divisionMatch.group(1)!.trim();
    final area = divisionMatch == null
        ? null
        : _normalizeArea(divisionMatch.group(2)!);

    final dayKey = '$year-$month-$day';
    final builder = days.putIfAbsent(
      dayKey,
      () => _DayBuilder(DateTime(year, month, day), weekday),
    );
    builder.add(division, time, SchedulePlace(venue: venue, area: area));
  }

  return days.values.map((b) => b.build()).toList(growable: false);
}

/// `서산,태안` → `서산·태안`. 빈 값이면 null.
String? _normalizeArea(String raw) {
  final parts = raw
      .split(',')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return null;
  return parts.join('·');
}

class _DayBuilder {
  _DayBuilder(this.date, this.weekday);

  final DateTime date;
  final String weekday;

  /// key: `부서|시간` — 같은 날 같은 부서라도 시간이 다르면 나눠 보여준다.
  final Map<String, List<SchedulePlace>> _places = {};
  final Map<String, ({String division, String time})> _keys = {};

  void add(String division, String time, SchedulePlace place) {
    final key = '$division|$time';
    _keys[key] = (division: division, time: time);
    _places.putIfAbsent(key, () => <SchedulePlace>[]).add(place);
  }

  ScheduleDay build() => ScheduleDay(
        date: date,
        weekday: weekday,
        divisions: [
          for (final entry in _keys.entries)
            ScheduleDivisionGroup(
              division: entry.value.division,
              time: entry.value.time,
              places: _places[entry.key]!,
            ),
        ],
      );
}
