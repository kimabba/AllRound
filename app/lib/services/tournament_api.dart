import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/match_record.dart';
import '../models/schedule_share.dart';
import '../models/tournament.dart';
import 'api_base.dart';

/// `tournaments-search` Edge Function 쿼리 파라미터를 조립한다.
///
/// 비어 있는 값은 키 자체를 생략한다(Edge Function 쿼리키:
/// region_code, org, division_codes, date_from, date_to, recruiting).
/// [recruiting] 은 'open' | 'closed' (null 이면 미전송).
/// 순수 함수 — 단위 테스트 가능.
Map<String, String> buildTournamentSearchQuery({
  String? sport,
  String? region,
  String? regionCode,
  DateTime? dateFrom,
  DateTime? dateTo,
  String? hostOrg,
  List<String> divisionCodes = const [],
  String? recruiting,
  bool onlyMyGrade = true,
  String? query,
  int limit = 50,
  int offset = 0,
}) {
  return {
    if (sport != null && sport.isNotEmpty) 'sport': sport,
    if (region != null && region.isNotEmpty) 'region': region,
    if (regionCode != null && regionCode.isNotEmpty) 'region_code': regionCode,
    if (dateFrom != null) 'date_from': _ymd(dateFrom),
    if (dateTo != null) 'date_to': _ymd(dateTo),
    if (hostOrg != null && hostOrg.isNotEmpty) 'org': hostOrg,
    if (divisionCodes.isNotEmpty) 'division_codes': divisionCodes.join(','),
    if (recruiting != null && recruiting.isNotEmpty) 'recruiting': recruiting,
    'only_my_grade': onlyMyGrade.toString(),
    if (query != null && query.isNotEmpty) 'q': query,
    'limit': limit.toString(),
    'offset': offset.toString(),
  };
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 대회·즐겨찾기·경기이력·일정공유 API.
mixin TournamentApi on ApiBase {
  // ── 검색 / 제출 / 승인 ───────────────────────────────────────

  Future<List<Tournament>> searchTournaments({
    String? sport,
    String? region,
    String? regionCode,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? hostOrg,
    List<String> divisionCodes = const [],
    String? recruiting,
    bool onlyMyGrade = true,
    String? query,
    int limit = 50,
    int offset = 0,
  }) async {
    final res = await http.get(
      uri(
        'tournaments-search',
        buildTournamentSearchQuery(
          sport: sport,
          region: region,
          regionCode: regionCode,
          dateFrom: dateFrom,
          dateTo: dateTo,
          hostOrg: hostOrg,
          divisionCodes: divisionCodes,
          recruiting: recruiting,
          onlyMyGrade: onlyMyGrade,
          query: query,
          limit: limit,
          offset: offset,
        ),
      ),
      headers: await authHeaders(),
    );
    check(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['tournaments'] as List)
        .map((e) => Tournament.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Tournament> submitTournament(Map<String, dynamic> payload) async {
    final res = await http.post(
      uri('tournaments-submit'),
      headers: await authHeaders(),
      body: jsonEncode(payload),
    );
    check(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return Tournament.fromJson(body['tournament'] as Map<String, dynamic>);
  }

  Future<void> approveTournament(String id,
      {bool approve = true, String? reason}) async {
    final res = await http.post(
      uri('tournaments-approve'),
      headers: await authHeaders(),
      body: jsonEncode({
        'id': id,
        'action': approve ? 'approve' : 'reject',
        if (reason != null) 'reason': reason,
      }),
    );
    check(res);
  }

  // ── 즐겨찾기 ─────────────────────────────────────────────────

  Future<void> toggleFavorite(String tournamentId, bool favorite) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Not authenticated');

    if (favorite) {
      await supabase.from('tournament_favorites').upsert({
        'user_id': userId,
        'tournament_id': tournamentId,
      });
    } else {
      await supabase
          .from('tournament_favorites')
          .delete()
          .eq('user_id', userId)
          .eq('tournament_id', tournamentId);
    }
  }

  Future<Set<String>> myFavoriteIds() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return {};
    final rows = await supabase
        .from('tournament_favorites')
        .select('tournament_id')
        .eq('user_id', userId);
    return rows.map((r) => r['tournament_id'] as String).toSet();
  }

  Future<List<Tournament>> myFavoriteTournaments({int? limit = 5}) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];
    var query = supabase
        .from('tournament_favorites')
        .select(
            'created_at, tournaments(*, tennis_tournament_details(*), futsal_tournament_details(*))')
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    if (limit != null) {
      query = query.limit(limit);
    }
    final rows = await query;

    return (rows as List)
        .map((row) => row as Map<String, dynamic>)
        .map((row) => row['tournaments'])
        .whereType<Map<String, dynamic>>()
        .map(Tournament.fromJson)
        .toList();
  }

  // ── 경기 이력 ─────────────────────────────────────────────────

  Future<List<MatchEntry>> myMatchEntries({int limit = 50}) async {
    final rows = await supabase
        .from('match_entries')
        .select('*, tournaments(title), match_rounds(*)')
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map((r) => MatchEntry.fromJson(r)).toList();
  }

  Future<MatchEntry> addMatchEntry({
    required String tournamentId,
    required String division,
    String? partnerId,
    String? partnerName,
    String? teamName,
    String? finalRound,
    int pointsEarned = 0,
  }) async {
    final userId = supabase.auth.currentUser!.id;
    final row = await supabase
        .from('match_entries')
        .insert({
          'user_id': userId,
          'tournament_id': tournamentId,
          'division': division,
          'partner_id': partnerId,
          'partner_name': partnerName,
          'team_name': teamName,
          'final_round': finalRound,
          'points_earned': pointsEarned,
        })
        .select('*, tournaments(title)')
        .single();
    return MatchEntry.fromJson(row);
  }

  Future<void> deleteMatchEntry(String entryId) async {
    await supabase.from('match_entries').delete().eq('id', entryId);
  }

  Future<MatchRound> addMatchRound({
    required String entryId,
    required String round,
    String? opponent1Name,
    String? opponent2Name,
    String? score,
    required String result,
    DateTime? playedAt,
  }) async {
    final row = await supabase
        .from('match_rounds')
        .insert({
          'entry_id': entryId,
          'round': round,
          'opponent_1_name': opponent1Name,
          'opponent_2_name': opponent2Name,
          'score': score,
          'result': result,
          'played_at': playedAt?.toIso8601String().substring(0, 10),
        })
        .select()
        .single();
    return MatchRound.fromJson(row);
  }

  Future<void> deleteMatchRound(String roundId) async {
    await supabase.from('match_rounds').delete().eq('id', roundId);
  }

  // ── 일정 공유 ─────────────────────────────────────────────────

  Future<void> shareSchedule({
    required String sharedWith,
    required String eventType,
    required String eventId,
  }) async {
    final userId = supabase.auth.currentUser!.id;
    await supabase.from('schedule_shares').upsert({
      'shared_by': userId,
      'shared_with': sharedWith,
      'event_type': eventType,
      'event_id': eventId,
    });
  }

  Future<List<ScheduleShare>> mySharedSchedules() async {
    final rows = await supabase
        .from('schedule_shares')
        .select(
            '*, shared_by_user:users!shared_by(name), shared_with_user:users!shared_with(name)')
        .order('created_at', ascending: false);
    return rows.map((r) => ScheduleShare.fromJson(r)).toList();
  }

  Future<void> respondToShare(String shareId, {required bool accept}) async {
    await supabase
        .from('schedule_shares')
        .update({'status': accept ? 'accepted' : 'declined'}).eq('id', shareId);
  }

  Future<void> deleteShare(String shareId) async {
    await supabase.from('schedule_shares').delete().eq('id', shareId);
  }
}
