/// 대회 요강 "전체 요강" 본문(regulation_body)의 줄 분류 로직.
///
/// 본문 텍스트엔 크롤러가 보존한 명확한 구조 마커(●/◎/◈/숫자./-/표 파이프 등)가
/// 있어, 키워드 기반 오쪼갬과 달리 안전하게 줄 단위로 분류할 수 있다.
/// UI(_RegulationBody)는 이 분류 결과를 받아 폰트 패밀리는 동일(bodyMedium)하게
/// 두고 weight·color·들여쓰기·세로간격으로만 위계를 표현한다.
///
/// 위젯을 public 화하지 않고도 분류 규칙을 단위 테스트할 수 있도록
/// 순수 함수(parseRegulationBody)로 분리한다.
library;

/// 한 줄의 종류.
enum RegulationLineKind {
  /// `●`/`◎` 로 시작하는 대분류 헤더.
  header,

  /// `◈` 로 시작하는 항목.
  item,

  /// `^\d+\.` 번호 목록.
  numbered,

  /// `^-\s?` 대시 하위 항목.
  dash,

  /// ` | ` 를 포함하는 표 데이터 행.
  tableRow,

  /// `라벨: 값` 형태.
  labelValue,

  /// 그 외 일반 문단.
  paragraph,

  /// `※` 로 시작하는 muted 노트.
  note,
}

/// 분류된 한 줄.
class RegulationLine {
  final RegulationLineKind kind;

  /// 마커 제거 후 표시 텍스트(헤더/항목/노트 등). tableRow 에선 미사용.
  final String text;

  /// numbered: 번호 라벨("1." 등) / labelValue: 라벨(콜론 제외).
  final String? label;

  /// labelValue: 값.
  final String? value;

  /// tableRow: 셀 목록(첫 셀이 헤더 셀).
  final List<String> cells;

  const RegulationLine({
    required this.kind,
    this.text = '',
    this.label,
    this.value,
    this.cells = const [],
  });
}

final _numbered = RegExp(r'^(\d+)\.\s*(.*)$');
final _dash = RegExp(r'^-\s?(.*)$');
// 라벨:값 — 라벨은 1~14자, 콜론/파이프 미포함, 콜론 뒤 공백.
final _labelValue = RegExp(r'^([^:|]{1,14}):\s+(.*)$');

/// 표 헤더 셀로 알려진 라벨(첫 셀이 이 중 하나면 헤더행으로 본다).
/// 예: "경기종목 | 경기일자 | 참가비 입금계좌" 의 첫 셀 "경기종목".
const _knownHeaderFirstCells = <String>{
  '경기종목',
  '종목',
  '부서',
  '부서명',
  '경기일자',
  '구분',
  '항목',
};

/// 표 헤더행인지 — 너무 광범위하게 잡지 않도록 좁힌다.
///
/// 이전엔 "셀에 숫자가 하나도 없으면 헤더"로 판정해, 실제 텍스트 파이프 행
/// (예: "남자부 | 여자부")까지 삭제됐다. 이제 **첫 셀이 알려진 헤더 라벨**일
/// 때만 헤더로 보고 생략한다. 일반 텍스트 파이프 행은 보존된다.
bool _isPureHeaderTable(List<String> cells) {
  if (cells.isEmpty) return false;
  return _knownHeaderFirstCells.contains(cells.first);
}

/// regulation_body 전체를 줄 단위로 분류한다.
/// - "\r\n" 정규화, 양끝 트림, 빈 줄 제외.
/// - 본문 중간에 "※" 가 있으면 "※" 앞부분은 규칙대로, "※ …" 조각들은 note 로 분리.
/// - 순수 헤더 표 행(데이터 자명)은 결과에서 제외.
List<RegulationLine> parseRegulationBody(String body) {
  final raw = body.replaceAll('\r\n', '\n').trim().split('\n');
  final out = <RegulationLine>[];

  for (final rawLine in raw) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;

    // ※ 분리: 앞부분 + 각 ※ 조각.
    if (line.contains('※')) {
      final firstIdx = line.indexOf('※');
      final before = line.substring(0, firstIdx).trim();
      if (before.isNotEmpty) {
        out.addAll(_classify(before));
      }
      // 나머지를 ※ 기준으로 분할.
      final rest = line.substring(firstIdx);
      for (final piece in rest.split('※')) {
        final p = piece.trim();
        if (p.isEmpty) continue;
        out.add(RegulationLine(kind: RegulationLineKind.note, text: '※ $p'));
      }
      continue;
    }

    out.addAll(_classify(line));
  }

  return out;
}

/// ※ 가 없는 단일 줄을 분류한다(0~1개 결과; 순수 헤더 표는 0개).
List<RegulationLine> _classify(String line) {
  // 1) 대분류 헤더 ● / ◎
  if (line.startsWith('●') || line.startsWith('◎')) {
    return [
      RegulationLine(
        kind: RegulationLineKind.header,
        text: line.substring(1).trim(),
      ),
    ];
  }

  // 2) 항목 ◈
  if (line.startsWith('◈')) {
    return [
      RegulationLine(
        kind: RegulationLineKind.item,
        text: line.substring(1).trim(),
      ),
    ];
  }

  // 3) 번호 목록 ^\d+\.
  final numMatch = _numbered.firstMatch(line);
  if (numMatch != null) {
    return [
      RegulationLine(
        kind: RegulationLineKind.numbered,
        label: '${numMatch.group(1)}.',
        text: (numMatch.group(2) ?? '').trim(),
      ),
    ];
  }

  // 4) 대시 하위 ^-\s?
  final dashMatch = _dash.firstMatch(line);
  if (dashMatch != null) {
    return [
      RegulationLine(
        kind: RegulationLineKind.dash,
        text: (dashMatch.group(1) ?? '').trim(),
      ),
    ];
  }

  // 5) 표 행 ' | '
  if (line.contains(' | ')) {
    final cells = line
        .split(' | ')
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList(growable: false);
    if (cells.isEmpty) return const [];
    // 순수 헤더행(숫자 없음)은 생략.
    if (_isPureHeaderTable(cells)) return const [];
    return [RegulationLine(kind: RegulationLineKind.tableRow, cells: cells)];
  }

  // 6) 라벨:값 (표 아님)
  final lvMatch = _labelValue.firstMatch(line);
  if (lvMatch != null) {
    return [
      RegulationLine(
        kind: RegulationLineKind.labelValue,
        label: (lvMatch.group(1) ?? '').trim(),
        value: (lvMatch.group(2) ?? '').trim(),
      ),
    ];
  }

  // 7) 일반 문단
  return [RegulationLine(kind: RegulationLineKind.paragraph, text: line)];
}

// 메타라인 머리("참가부서:" 등) — 카드와 중복되는 줄 판정용.
final _metaLineHead = RegExp(r'^(참가부서|신청마감|접수마감|대회일|지역)\s*:');

// 부서별 접수 항목 시작 직전("… 남자단체전 2026년 …")의 공백.
final _beforeDivisionEntry = RegExp(
  r'\s+(?=(?:남자|여자)?(?:단체전|일반부|오픈부|신인부|골드부|지도자부|'
  r'마스터즈부|베테랑부|크로스대회)\s*\d{4}\s*년)',
);

/// 구조화 데이터가 없는 단순 공고의 평문 description 을 보기 좋게 정리한다.
/// - 카드와 중복되는 메타라인("참가부서:.. | 신청마감:.. | 대회일:.. | 지역:..") 제거
/// - 부서별 접수 항목("남자단체전 2026년 …") 앞에서 줄바꿈
/// 마커가 없는 일반 텍스트는 문단을 그대로 유지(과한 가공 금지).
/// 정리 결과가 비면 빈 리스트 → 호출부는 원문 폴백.
List<String> cleanPlainRegulationLines(String description) {
  final normalized = description.replaceAll('\r\n', '\n').trim();
  if (normalized.isEmpty) return const [];

  // 1) 중복 메타라인 제거: 빈 줄로 나눈 첫 블록이 메타라인이면 버린다.
  final blocks = normalized.split(RegExp(r'\n{2,}'));
  if (blocks.length > 1 &&
      blocks.first.contains(' | ') &&
      _metaLineHead.hasMatch(blocks.first.trim())) {
    blocks.removeAt(0);
  }
  var body = blocks.join('\n\n').trim();
  if (body.isEmpty) return const [];

  // 2) 부서 접수 항목 앞에서 줄바꿈.
  body = body.replaceAll(_beforeDivisionEntry, '\n');

  // 3) 줄 단위 공백 정규화.
  return body
      .split('\n')
      .map((l) => l.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
      .where((l) => l.isNotEmpty)
      .toList(growable: false);
}
