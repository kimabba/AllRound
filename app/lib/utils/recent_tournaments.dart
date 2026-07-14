import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/tournament.dart';

class RecentTournamentEntry {
  const RecentTournamentEntry({
    required this.id,
    required this.sport,
    required this.title,
    required this.startDate,
    required this.viewedAt,
    this.applicationDeadline,
    this.region,
    this.location,
  });

  final String id;
  final String sport;
  final String title;
  final DateTime startDate;
  final DateTime viewedAt;
  final DateTime? applicationDeadline;
  final String? region;
  final String? location;

  factory RecentTournamentEntry.fromTournament(
    Tournament tournament,
    DateTime viewedAt,
  ) {
    return RecentTournamentEntry(
      id: tournament.id,
      sport: tournament.sport,
      title: tournament.title,
      startDate: tournament.startDate,
      viewedAt: viewedAt,
      applicationDeadline: tournament.applicationDeadline,
      region: tournament.region,
      location: tournament.location,
    );
  }

  static RecentTournamentEntry? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final sport = raw['sport'];
    final title = raw['title'];
    final startDate = raw['start_date'];
    final viewedAt = raw['viewed_at'];
    if (id is! String ||
        sport is! String ||
        title is! String ||
        startDate is! String ||
        viewedAt is! String) {
      return null;
    }
    final parsedStartDate = DateTime.tryParse(startDate);
    final parsedViewedAt = DateTime.tryParse(viewedAt);
    if (parsedStartDate == null || parsedViewedAt == null) return null;
    final deadline = raw['application_deadline'];
    return RecentTournamentEntry(
      id: id,
      sport: sport,
      title: title,
      startDate: parsedStartDate,
      viewedAt: parsedViewedAt,
      applicationDeadline:
          deadline is String ? DateTime.tryParse(deadline) : null,
      region: raw['region'] is String ? raw['region'] as String : null,
      location: raw['location'] is String ? raw['location'] as String : null,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'sport': sport,
        'title': title,
        'start_date': startDate.toIso8601String(),
        'viewed_at': viewedAt.toIso8601String(),
        'application_deadline': applicationDeadline?.toIso8601String(),
        'region': region,
        'location': location,
      };
}

class RecentTournamentStore {
  const RecentTournamentStore(this._preferences);

  static const maxEntries = 10;
  static const _keyPrefix = 'tournaments.recent.v1';

  final SharedPreferences _preferences;

  static Future<RecentTournamentStore> create() async {
    return RecentTournamentStore(await SharedPreferences.getInstance());
  }

  List<RecentTournamentEntry> load(String userId) {
    final encoded = _preferences.getString(_key(userId));
    if (encoded == null || encoded.isEmpty) return const [];
    try {
      final Object? decoded = jsonDecode(encoded);
      if (decoded is! List) return const [];
      return decoded
          .map(RecentTournamentEntry.tryFromJson)
          .whereType<RecentTournamentEntry>()
          .take(maxEntries)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> record(
    String userId,
    Tournament tournament, {
    DateTime? viewedAt,
  }) async {
    final entry = RecentTournamentEntry.fromTournament(
      tournament,
      viewedAt ?? DateTime.now(),
    );
    final entries = [
      entry,
      ...load(userId).where((item) => item.id != tournament.id),
    ].take(maxEntries).toList(growable: false);
    await _preferences.setString(
      _key(userId),
      jsonEncode(entries.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> clear(String userId) => _preferences.remove(_key(userId));

  String _key(String userId) => '$_keyPrefix.$userId';
}
