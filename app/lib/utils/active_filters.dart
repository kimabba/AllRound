/// 상세검색 활성 필터 → 결과 화면 요약 칩 데이터(순수 로직).
///
/// 화면 상태에서 "현재 적용 중인 필터"를 사람이 읽을 수 있는 칩 목록으로
/// 산출한다. 각 칩은 제거 대상을 식별할 수 있는 kind(+value)를 가진다.
/// UI 위젯과 분리해 단위 테스트가 가능하다.
library;

import 'grade_labels.dart';
import 'tournament_filters.dart';

/// 요약 칩의 종류. 제거 시 어떤 필터를 해제할지 식별한다.
enum ActiveFilterKind {
  query,
  region,
  dateRange,
  hostOrg,
  division, // value = 부서 라벨(테니스) 또는 grade 코드(풋살) — source of truth
  recruiting,
  onlyMyGrade,
}

/// 결과 화면 요약 칩 1개.
class ActiveFilterChipData {
  final ActiveFilterKind kind;

  /// division 칩에서 제거 대상 식별값(부서 라벨 또는 등급 코드). 그 외엔 null.
  final String? value;

  /// 칩 표시 라벨.
  final String label;

  const ActiveFilterChipData({
    required this.kind,
    required this.label,
    this.value,
  });

  @override
  bool operator ==(Object other) =>
      other is ActiveFilterChipData &&
      other.kind == kind &&
      other.value == value &&
      other.label == label;

  @override
  int get hashCode => Object.hash(kind, value, label);

  @override
  String toString() => 'ActiveFilterChip($kind, $value, "$label")';
}

String _formatYmd(DateTime d) =>
    '${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

/// 기간 칩 라벨: 표준 프리셋이면 프리셋명("당월"), 아니면 범위("06.01~06.30").
String dateRangeChipLabel(DateTime? from, DateTime? to, DateTime now) {
  final preset = presetForRange(from, to, now);
  if (preset != DatePreset.all && preset != DatePreset.custom) {
    return datePresetLabel(preset);
  }
  if (from != null && to != null) {
    return '${_formatYmd(from)}~${_formatYmd(to)}';
  }
  return '기간';
}

/// 현재 필터 상태 → 활성 요약 칩 목록.
///
/// [sport] 는 'tennis' | 'futsal' (division 라벨 표시 방식 결정).
/// [divisionLabels] 는 source of truth(테니스: 부서 라벨, 풋살: grade 코드).
/// 칩 순서: 검색어 → 지역 → 기간 → 협회 → 부서(라벨별) → 모집상태 → 내 등급만.
List<ActiveFilterChipData> activeFilterChips({
  required String? sport,
  required String query,
  required String? regionCode,
  required DateTime? dateFrom,
  required DateTime? dateTo,
  required String? hostOrg,
  required Set<String> divisionLabels,
  required RecruitingStatus recruiting,
  required bool onlyMyGrade,
  required DateTime now,
}) {
  final chips = <ActiveFilterChipData>[];
  final isTennis = sport == 'tennis';

  final trimmedQuery = query.trim();
  if (trimmedQuery.isNotEmpty) {
    chips.add(ActiveFilterChipData(
      kind: ActiveFilterKind.query,
      label: '"$trimmedQuery"',
    ));
  }

  if (regionCode != null) {
    chips.add(ActiveFilterChipData(
      kind: ActiveFilterKind.region,
      label: regionLabel(regionCode),
    ));
  }

  if (dateFrom != null || dateTo != null) {
    chips.add(ActiveFilterChipData(
      kind: ActiveFilterKind.dateRange,
      label: dateRangeChipLabel(dateFrom, dateTo, now),
    ));
  }

  if (hostOrg != null) {
    chips.add(ActiveFilterChipData(
      kind: ActiveFilterKind.hostOrg,
      label: tennisOrgShortLabel(hostOrg),
    ));
  }

  // 부서/등급: 라벨 단위로 개별 칩. value 는 source-of-truth 라벨/grade.
  // 테니스: 라벨이 곧 표시명. 풋살: grade 코드 → 한글 라벨 표시.
  for (final value in divisionLabels) {
    chips.add(ActiveFilterChipData(
      kind: ActiveFilterKind.division,
      value: value,
      label: isTennis ? value : gradeLabel(value),
    ));
  }

  if (recruiting != RecruitingStatus.all) {
    chips.add(ActiveFilterChipData(
      kind: ActiveFilterKind.recruiting,
      label: recruitingStatusLabel(recruiting),
    ));
  }

  if (onlyMyGrade) {
    chips.add(const ActiveFilterChipData(
      kind: ActiveFilterKind.onlyMyGrade,
      label: '내 등급만',
    ));
  }

  return chips;
}
