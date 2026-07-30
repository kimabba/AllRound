Uri buildGoogleCalendarUrl({
  required String title,
  required DateTime startsAt,
  Duration duration = const Duration(hours: 2),
  String? description,
  String? location,
}) {
  final start = startsAt.toUtc();
  final end = start.add(duration);
  return Uri.https('calendar.google.com', '/calendar/render', {
    'action': 'TEMPLATE',
    'text': title,
    'dates': '${_googleDate(start)}/${_googleDate(end)}',
    if (description != null && description.trim().isNotEmpty)
      'details': description.trim(),
    if (location != null && location.trim().isNotEmpty)
      'location': location.trim(),
  });
}

String _googleDate(DateTime value) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}'
      '${twoDigits(value.month)}'
      '${twoDigits(value.day)}T'
      '${twoDigits(value.hour)}'
      '${twoDigits(value.minute)}'
      '${twoDigits(value.second)}Z';
}
