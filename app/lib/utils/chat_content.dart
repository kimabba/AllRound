/// Removes internal database identifiers from user-visible assistant text.
String cleanAssistantContent(String content) {
  if (content.isEmpty) return '…';

  final parenthesizedId = RegExp(
    r'\(\s*id\s*:\s*[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\s*\)',
    caseSensitive: false,
  );

  return content
      .replaceAll(parenthesizedId, '')
      .replaceAll(RegExp(r'\(출처:?\s*(?:id\s*)?[a-f0-9\-,\s]+\)'), '')
      .replaceAll(
        RegExp(
          r'출처:\s*(?:id\s+)?[a-f0-9\-]+(?:,\s*(?:id\s+)?[a-f0-9\-]+)*',
        ),
        '',
      )
      .trim();
}
