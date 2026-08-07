import 'regulation_body_lines.dart';

enum RegulationSectionCode {
  eligibility('eligibility', '참가 부서 및 자격'),
  scheduleVenue('schedule_venue', '일정 및 장소'),
  registrationPayment('registration_payment', '신청 및 결제'),
  matchOperations('match_operations', '경기 방식 및 운영'),
  awards('awards', '시상 및 참가상품'),
  refundChanges('refund_changes', '변경·취소·환불'),
  noticesContact('notices_contact', '유의사항 및 문의'),
  other('other', '기타 안내');

  const RegulationSectionCode(this.value, this.label);

  final String value;
  final String label;

  static RegulationSectionCode? tryParse(Object? value) {
    if (value is! String) return null;
    for (final code in values) {
      if (code.value == value) return code;
    }
    return null;
  }
}

enum RegulationAvailability {
  present,
  notAnnounced,
  notApplicable;

  static RegulationAvailability? tryParse(Object? value) => switch (value) {
        'present' => RegulationAvailability.present,
        'not_announced' => RegulationAvailability.notAnnounced,
        'not_applicable' => RegulationAvailability.notApplicable,
        _ => null,
      };
}

enum RegulationBlockType {
  paragraph,
  subheading,
  bullets,
  keyValues,
  table,
  notice,
  divisionSchedule;

  static RegulationBlockType? tryParse(Object? value) => switch (value) {
        'paragraph' => RegulationBlockType.paragraph,
        'subheading' => RegulationBlockType.subheading,
        'bullets' => RegulationBlockType.bullets,
        'key_values' => RegulationBlockType.keyValues,
        'table' => RegulationBlockType.table,
        'notice' => RegulationBlockType.notice,
        'division_schedule' => RegulationBlockType.divisionSchedule,
        _ => null,
      };
}

class RegulationDocument {
  const RegulationDocument({
    required this.schemaVersion,
    required this.sections,
    this.summary,
  });

  static const currentSchemaVersion = 1;

  final int schemaVersion;
  final String? summary;
  final List<RegulationSection> sections;

  bool get isEmpty => sections.isEmpty;

  static RegulationDocument? tryFromJson(Object? raw) {
    final json = _map(raw);
    if (json == null || json['schema_version'] != currentSchemaVersion) {
      return null;
    }
    final rawSections = json['sections'];
    if (rawSections is! List) return null;

    final byCode = <RegulationSectionCode, RegulationSection>{};
    for (final rawSection in rawSections) {
      final section = RegulationSection.tryFromJson(rawSection);
      if (section == null) continue;
      byCode.putIfAbsent(section.code, () => section);
    }
    final sections = RegulationSectionCode.values
        .map((code) => byCode[code])
        .whereType<RegulationSection>()
        .toList(growable: false);
    if (sections.isEmpty) return null;
    return RegulationDocument(
      schemaVersion: currentSchemaVersion,
      summary: _text(json['summary']),
      sections: sections,
    );
  }

  static RegulationDocument? fromLegacy({
    required List<({String label, String value})> fields,
    required List<String> notes,
    String? body,
  }) {
    final grouped = <RegulationSectionCode, List<RegulationEntry>>{};
    for (final field in fields) {
      final label = field.label.trim();
      final value = field.value.trim();
      if (label.isEmpty || value.isEmpty) continue;
      final code = sectionCodeForLegacyLabel(label);
      grouped.putIfAbsent(code, () => []).add(
            RegulationEntry(label: label, value: value),
          );
    }

    final sections = <RegulationSection>[];
    for (final code in RegulationSectionCode.values) {
      final entries = grouped[code];
      if (entries == null || entries.isEmpty) continue;
      sections.add(
        RegulationSection(
          code: code,
          availability: RegulationAvailability.present,
          blocks: [
            RegulationBlock(
              type: RegulationBlockType.keyValues,
              entries: entries,
            ),
          ],
        ),
      );
    }

    final cleanNotes = notes
        .map((note) => note.trim())
        .where((note) => note.isNotEmpty)
        .toList();
    if (cleanNotes.isNotEmpty) {
      _appendBlock(
        sections,
        RegulationSectionCode.noticesContact,
        RegulationBlock(type: RegulationBlockType.bullets, items: cleanNotes),
      );
    }
    final cleanBody = body?.trim();
    if (cleanBody != null && cleanBody.isNotEmpty) {
      for (final block in _legacyBodyBlocks(cleanBody)) {
        _appendBlock(sections, RegulationSectionCode.other, block);
      }
    }
    sections.sort((a, b) => a.code.index.compareTo(b.code.index));
    if (sections.isEmpty) return null;
    return RegulationDocument(
      schemaVersion: currentSchemaVersion,
      sections: List.unmodifiable(sections),
    );
  }

  static void _appendBlock(
    List<RegulationSection> sections,
    RegulationSectionCode code,
    RegulationBlock block,
  ) {
    final index = sections.indexWhere((section) => section.code == code);
    if (index < 0) {
      sections.add(
        RegulationSection(
          code: code,
          availability: RegulationAvailability.present,
          blocks: [block],
        ),
      );
      return;
    }
    final section = sections[index];
    sections[index] = RegulationSection(
      code: section.code,
      availability: section.availability,
      blocks: [...section.blocks, block],
    );
  }
}

List<RegulationBlock> _legacyBodyBlocks(String body) {
  final blocks = <RegulationBlock>[];
  for (final line in publicRegulationBodyLines(body)) {
    switch (line.kind) {
      case RegulationLineKind.header:
      case RegulationLineKind.item:
        blocks.add(
          RegulationBlock(
            type: RegulationBlockType.subheading,
            text: line.text,
          ),
        );
        break;
      case RegulationLineKind.numbered:
        blocks.add(
          RegulationBlock(
            type: RegulationBlockType.bullets,
            items: ['${line.label ?? ''} ${line.text}'.trim()],
          ),
        );
        break;
      case RegulationLineKind.dash:
        blocks.add(
          RegulationBlock(
            type: RegulationBlockType.bullets,
            items: [line.text],
          ),
        );
        break;
      case RegulationLineKind.tableRow:
        blocks.add(
          RegulationBlock(
            type: RegulationBlockType.table,
            rows: [RegulationTableRow(cells: line.cells)],
          ),
        );
        break;
      case RegulationLineKind.labelValue:
        final label = line.label;
        final value = line.value;
        if (label != null && value != null) {
          blocks.add(
            RegulationBlock(
              type: RegulationBlockType.keyValues,
              entries: [RegulationEntry(label: label, value: value)],
            ),
          );
        }
        break;
      case RegulationLineKind.paragraph:
        blocks.add(
          RegulationBlock(
            type: RegulationBlockType.paragraph,
            text: line.text,
          ),
        );
        break;
      case RegulationLineKind.note:
        break;
    }
  }
  return blocks;
}

class RegulationSection {
  const RegulationSection({
    required this.code,
    required this.availability,
    required this.blocks,
  });

  final RegulationSectionCode code;
  final RegulationAvailability availability;
  final List<RegulationBlock> blocks;

  static RegulationSection? tryFromJson(Object? raw) {
    final json = _map(raw);
    if (json == null) return null;
    final code = RegulationSectionCode.tryParse(json['code']);
    final availability = RegulationAvailability.tryParse(json['availability']);
    if (code == null || availability == null) return null;
    final rawBlocks = json['blocks'];
    final blocks = rawBlocks is List
        ? rawBlocks
            .map(RegulationBlock.tryFromJson)
            .whereType<RegulationBlock>()
            .toList(growable: false)
        : const <RegulationBlock>[];
    if (availability == RegulationAvailability.present && blocks.isEmpty) {
      return null;
    }
    return RegulationSection(
      code: code,
      availability: availability,
      blocks: blocks,
    );
  }
}

class RegulationBlock {
  const RegulationBlock({
    required this.type,
    this.text,
    this.items = const [],
    this.entries = const [],
    this.columns = const [],
    this.rows = const [],
    this.divisions = const [],
  });

  final RegulationBlockType type;
  final String? text;
  final List<String> items;
  final List<RegulationEntry> entries;
  final List<String> columns;
  final List<RegulationTableRow> rows;
  final List<RegulationDivisionItem> divisions;

  static RegulationBlock? tryFromJson(Object? raw) {
    final json = _map(raw);
    if (json == null) return null;
    final type = RegulationBlockType.tryParse(json['type']);
    if (type == null) return null;
    final text = _text(json['text']);
    final items = _strings(json['items']);
    final entries = _objects(json['entries'], RegulationEntry.tryFromJson);
    final rows = _objects(json['rows'], RegulationTableRow.tryFromJson);
    final divisions = _objects(
      json['divisions'],
      RegulationDivisionItem.tryFromJson,
    );
    final columns = _strings(json['columns']);
    final hasContent = switch (type) {
      RegulationBlockType.paragraph ||
      RegulationBlockType.subheading ||
      RegulationBlockType.notice =>
        text != null,
      RegulationBlockType.bullets => items.isNotEmpty,
      RegulationBlockType.keyValues => entries.isNotEmpty,
      RegulationBlockType.table => rows.isNotEmpty,
      RegulationBlockType.divisionSchedule => divisions.isNotEmpty,
    };
    if (!hasContent) return null;
    return RegulationBlock(
      type: type,
      text: text,
      items: items,
      entries: entries,
      columns: columns,
      rows: rows,
      divisions: divisions,
    );
  }
}

class RegulationEntry {
  const RegulationEntry({required this.label, required this.value});

  final String label;
  final String value;

  static RegulationEntry? tryFromJson(Object? raw) {
    final json = _map(raw);
    if (json == null) return null;
    final label = _text(json['label']);
    final value = _text(json['value']);
    return label == null || value == null
        ? null
        : RegulationEntry(label: label, value: value);
  }
}

class RegulationTableRow {
  const RegulationTableRow({required this.cells});

  final List<String> cells;

  static RegulationTableRow? tryFromJson(Object? raw) {
    final json = _map(raw);
    if (json == null) return null;
    final cells = _strings(json['cells']);
    return cells.isEmpty ? null : RegulationTableRow(cells: cells);
  }
}

class RegulationDivisionItem {
  const RegulationDivisionItem({
    required this.name,
    this.date,
    this.venue,
    this.fee,
    this.account,
    this.capacity,
  });

  final String name;
  final String? date;
  final String? venue;
  final String? fee;
  final String? account;
  final String? capacity;

  static RegulationDivisionItem? tryFromJson(Object? raw) {
    final json = _map(raw);
    if (json == null) return null;
    final name = _text(json['name']);
    if (name == null) return null;
    return RegulationDivisionItem(
      name: name,
      date: _text(json['date']),
      venue: _text(json['venue']),
      fee: _text(json['fee']),
      account: _text(json['account']),
      capacity: _text(json['capacity']),
    );
  }
}

RegulationSectionCode sectionCodeForLegacyLabel(String label) {
  final value = label.toLowerCase().replaceAll(RegExp(r'[\s_\-·:/()]'), '');
  if (RegExp(r'참가부서|참가자격|출전규정|예외부서|시드기준|참가규모|경기종목').hasMatch(value)) {
    return RegulationSectionCode.eligibility;
  }
  if (RegExp(r'일시|일정|대회일|경기일|장소|경기장|개최지').hasMatch(value)) {
    return RegulationSectionCode.scheduleVenue;
  }
  if (RegExp(r'환불|취소|변경').hasMatch(value)) {
    return RegulationSectionCode.refundChanges;
  }
  if (RegExp(r'신청|접수|참가비|입금|계좌|결제|예금주').hasMatch(value)) {
    return RegulationSectionCode.registrationPayment;
  }
  if (RegExp(r'시상|상금|참가상품|기념품').hasMatch(value)) {
    return RegulationSectionCode.awards;
  }
  if (RegExp(r'경기방식|진행방식|운영|사용구|주최|주관|후원|협찬').hasMatch(value)) {
    return RegulationSectionCode.matchOperations;
  }
  if (RegExp(r'문의|연락|전화|담당|안내').hasMatch(value)) {
    return RegulationSectionCode.noticesContact;
  }
  return RegulationSectionCode.other;
}

Map<Object?, Object?>? _map(Object? value) => value is Map ? value : null;

String? _text(Object? value) {
  if (value is! String) return null;
  final text = value.trim();
  return text.isEmpty ? null : text;
}

List<String> _strings(Object? value) => value is List
    ? value.map(_text).whereType<String>().toList(growable: false)
    : const [];

List<T> _objects<T>(Object? value, T? Function(Object?) parse) => value is List
    ? value.map(parse).whereType<T>().toList(growable: false)
    : const [];
