class FormatReviewItem {
  const FormatReviewItem({
    required this.id,
    required this.title,
    required this.sourceUrl,
    required this.sourceHash,
    required this.staged,
    required this.flags,
  });

  factory FormatReviewItem.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('format review id is required');
    }

    final sourceUrl = _httpUri(json['source_url']);
    final stagedJson = _jsonMap(json['format_staged']);
    final flagValues = json['format_flags'];

    return FormatReviewItem(
      id: id,
      title: _nonEmptyString(json['title']) ?? '제목 없는 대회',
      sourceUrl: sourceUrl,
      sourceHash: _nonEmptyString(json['format_source_hash']),
      staged: stagedJson == null ? null : StagedRegulation.fromJson(stagedJson),
      flags: flagValues is List
          ? flagValues
                .map(_jsonMap)
                .whereType<Map<String, dynamic>>()
                .map(FormatReviewFlag.fromJson)
                .toList(growable: false)
          : const <FormatReviewFlag>[],
    );
  }

  final String id;
  final String title;
  final Uri? sourceUrl;
  final String? sourceHash;
  final StagedRegulation? staged;
  final List<FormatReviewFlag> flags;
}

class StagedRegulation {
  const StagedRegulation({
    required this.fields,
    required this.description,
    required this.notes,
    required this.body,
    required this.prize,
    required this.format,
  });

  factory StagedRegulation.fromJson(Map<String, dynamic> json) {
    final fieldValues = json['regulation_fields'];
    final noteValues = json['regulation_notes'];

    return StagedRegulation(
      fields: fieldValues is List
          ? fieldValues
                .map(_jsonMap)
                .whereType<Map<String, dynamic>>()
                .map(RegulationField.fromJson)
                .where(
                  (field) => field.label.isNotEmpty && field.value.isNotEmpty,
                )
                .toList(growable: false)
          : const <RegulationField>[],
      description: _nonEmptyString(json['description']),
      notes: noteValues is List
          ? noteValues
                .map(_nonEmptyString)
                .whereType<String>()
                .toList(growable: false)
          : const <String>[],
      body: _nonEmptyString(json['regulation_body']),
      prize: _nonEmptyString(json['prize']),
      format: _nonEmptyString(json['format']),
    );
  }

  final List<RegulationField> fields;
  final String? description;
  final List<String> notes;
  final String? body;
  final String? prize;
  final String? format;
}

class RegulationField {
  const RegulationField({required this.label, required this.value});

  factory RegulationField.fromJson(Map<String, dynamic> json) {
    return RegulationField(
      label: _nonEmptyString(json['label']) ?? '',
      value: _nonEmptyString(json['value']) ?? '',
    );
  }

  final String label;
  final String value;
}

class FormatReviewFlag {
  const FormatReviewFlag({
    required this.code,
    required this.field,
    required this.masked,
  });

  factory FormatReviewFlag.fromJson(Map<String, dynamic> json) {
    return FormatReviewFlag(
      code: _nonEmptyString(json['code']) ?? 'unknown',
      field: _nonEmptyString(json['field']) ?? '알 수 없는 항목',
      masked: _nonEmptyString(json['masked']),
    );
  }

  final String code;
  final String field;
  final String? masked;
}

Map<String, dynamic>? _jsonMap(Object? value) {
  if (value is! Map) return null;
  return value.map((key, item) => MapEntry(key.toString(), item));
}

String? _nonEmptyString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

Uri? _httpUri(Object? value) {
  final raw = _nonEmptyString(value);
  if (raw == null) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  return uri;
}
