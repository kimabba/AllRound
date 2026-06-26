import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/club_event.dart';
import '../models/club_post.dart';
import '../models/tournament.dart';
import 'api_base.dart';

/// 클럽 CRUD·가입·멤버·이벤트·게시판·즐겨찾기 API.
mixin ClubApi on ApiBase {
  // ── 검색 / 생성 ──────────────────────────────────────────────

  Future<List<Club>> searchClubs(
      {String? sport, String? region, String? q}) async {
    final res = await http.get(
      uri('clubs-search', {
        if (sport != null) 'sport': sport,
        if (region != null) 'region': region,
        if (q != null && q.isNotEmpty) 'q': q,
      }),
      headers: await authHeaders(),
    );
    check(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['clubs'] as List)
        .map((e) => Club.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Club>> myClubs() async {
    final res = await http.get(
      uri('clubs-search', {'mine': 'true'}),
      headers: await authHeaders(),
    );
    check(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['clubs'] as List)
        .map((e) => Club.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Club> createClub({
    required String sport,
    required String name,
    String? region,
    String? address,
    String? logoUrl,
    String? contact,
    String? website,
    String? description,
    List<String>? meetingDays,
    int? monthlyFee,
    String? genderPreference,
  }) async {
    final res = await http.post(
      uri('clubs-create'),
      headers: await authHeaders(),
      body: jsonEncode({
        'sport': sport,
        'name': name,
        if (region != null && region.isNotEmpty) 'region': region,
        if (address != null && address.isNotEmpty) 'address': address,
        if (logoUrl != null && logoUrl.isNotEmpty) 'logo_url': logoUrl,
        if (contact != null && contact.isNotEmpty) 'contact': contact,
        if (website != null && website.isNotEmpty) 'website': website,
        if (description != null && description.isNotEmpty)
          'description': description,
        if (meetingDays != null && meetingDays.isNotEmpty)
          'meeting_days': meetingDays,
        if (monthlyFee != null) 'monthly_fee': monthlyFee,
        if (genderPreference != null && genderPreference.isNotEmpty)
          'gender_preference': genderPreference,
      }),
    );
    check(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return Club.fromJson(body['club'] as Map<String, dynamic>);
  }

  Future<String> uploadClubLogo({
    required Uint8List bytes,
    required String extension,
    required String contentType,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Not authenticated');

    final safeExt = extension.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final ext = safeExt.isEmpty ? 'jpg' : safeExt.toLowerCase();
    final path = '$userId/${DateTime.now().millisecondsSinceEpoch}.$ext';

    await supabase.storage.from('club-logos').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: true,
          ),
        );
    return supabase.storage.from('club-logos').getPublicUrl(path);
  }

  // ── 가입 / 탈퇴 ──────────────────────────────────────────────

  Future<void> joinClub(String clubId, {String? message}) async {
    final res = await http.post(
      uri('clubs-join'),
      headers: await authHeaders(),
      body: jsonEncode({
        'club_id': clubId,
        'action': 'request',
        if (message != null && message.isNotEmpty) 'message': message,
      }),
    );
    check(res);
  }

  Future<void> cancelJoinClub(String clubId) async {
    final res = await http.post(
      uri('clubs-join'),
      headers: await authHeaders(),
      body: jsonEncode({'club_id': clubId, 'action': 'cancel'}),
    );
    check(res);
  }

  Future<void> leaveClub(String clubId) async {
    final res = await http.post(
      uri('clubs-join'),
      headers: await authHeaders(),
      body: jsonEncode({'club_id': clubId, 'action': 'leave'}),
    );
    check(res);
  }

  Future<void> kickMember(String clubId, String targetUserId) async {
    final res = await http.post(
      uri('clubs-join'),
      headers: await authHeaders(),
      body: jsonEncode({
        'club_id': clubId,
        'action': 'kick',
        'target_user_id': targetUserId,
      }),
    );
    check(res);
  }

  Future<List<Map<String, dynamic>>> pendingJoinRequests(String clubId) async {
    final rows = await supabase
        .from('club_join_requests')
        .select('id, user_id, message, created_at, users(name, email)')
        .eq('club_id', clubId)
        .eq('status', 'pending')
        .order('created_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> reviewJoinRequest(String requestId,
      {required bool approve, String? reason}) async {
    final res = await http.post(
      uri('clubs-review-join'),
      headers: await authHeaders(),
      body: jsonEncode({
        'request_id': requestId,
        'action': approve ? 'approve' : 'reject',
        if (reason != null) 'reason': reason,
      }),
    );
    check(res);
  }

  // ── 멤버 / 이벤트 ────────────────────────────────────────────

  Future<List<ClubMember>> clubMembers(String clubId) async {
    final rows = await supabase
        .from('club_members')
        .select('user_id, role, joined_at, users(name)')
        .eq('club_id', clubId)
        .eq('status', 'active')
        .order('joined_at');
    final members =
        List<Map<String, dynamic>>.from(rows).map(ClubMember.fromJson).toList();
    const rank = {'owner': 0, 'manager': 1, 'member': 2};
    members.sort((a, b) => (rank[a.role] ?? 3).compareTo(rank[b.role] ?? 3));
    return members;
  }

  Future<List<ClubEvent>> clubEvents(String clubId) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final rows = await supabase
        .from('club_events')
        .select('*, club_event_attendees(user_id, status)')
        .eq('club_id', clubId)
        .gte('starts_at', nowIso)
        .order('starts_at');
    final uid = supabase.auth.currentUser?.id;
    return List<Map<String, dynamic>>.from(rows)
        .map((j) => ClubEvent.fromJson(j, currentUserId: uid))
        .toList();
  }

  Future<void> createClubEvent({
    required String clubId,
    required String title,
    String? description,
    String? locationText,
    required DateTime startsAt,
  }) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) throw StateError('Not authenticated');
    await supabase.from('club_events').insert({
      'club_id': clubId,
      'created_by': uid,
      'title': title,
      if (description != null && description.isNotEmpty)
        'description': description,
      if (locationText != null && locationText.isNotEmpty)
        'location_text': locationText,
      'starts_at': startsAt.toUtc().toIso8601String(),
    });
  }

  Future<void> respondEvent(String eventId, {required bool going}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) throw StateError('Not authenticated');
    await supabase.from('club_event_attendees').upsert({
      'event_id': eventId,
      'user_id': uid,
      'status': going ? 'going' : 'not_going',
      'responded_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'event_id,user_id');
  }

  // ── 즐겨찾기 ─────────────────────────────────────────────────

  Future<void> toggleClubFavorite(String clubId, bool favorite) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Not authenticated');

    if (favorite) {
      await supabase.from('club_favorites').upsert({
        'user_id': userId,
        'club_id': clubId,
      });
    } else {
      await supabase
          .from('club_favorites')
          .delete()
          .eq('user_id', userId)
          .eq('club_id', clubId);
    }
  }

  Future<Set<String>> myClubFavoriteIds() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return {};
    final rows = await supabase
        .from('club_favorites')
        .select('club_id')
        .eq('user_id', userId);
    return rows.map((r) => r['club_id'] as String).toSet();
  }

  Future<List<Club>> myFavoriteClubs({int? limit = 50}) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];
    var query = supabase
        .from('club_favorites')
        .select('created_at, clubs(*)')
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    if (limit != null) {
      query = query.limit(limit);
    }
    final rows = await query;

    return (rows as List)
        .map((row) => row as Map<String, dynamic>)
        .map((row) => row['clubs'])
        .whereType<Map<String, dynamic>>()
        .map(Club.fromJson)
        .toList();
  }

  // ── 게시판 ────────────────────────────────────────────────────

  Future<List<ClubPost>> clubPosts(String clubId, {String? tag}) async {
    var query = supabase
        .from('club_posts')
        .select('*, users!author_id(name), club_post_comments(id)')
        .eq('club_id', clubId);
    if (tag != null) query = query.eq('tag', tag);
    final rows = await query.order('created_at', ascending: false).limit(50);
    return rows.map((r) => ClubPost.fromJson(r)).toList();
  }

  Future<ClubPost> createPost({
    required String clubId,
    required String tag,
    required String title,
    required String body,
    List<String> imageUrls = const [],
  }) async {
    final userId = supabase.auth.currentUser!.id;
    final row = await supabase
        .from('club_posts')
        .insert({
          'club_id': clubId,
          'author_id': userId,
          'tag': tag,
          'title': title,
          'body': body,
          'image_urls': imageUrls,
        })
        .select('*, users!author_id(name)')
        .single();
    return ClubPost.fromJson(row);
  }

  Future<void> deletePost(String postId) async {
    await supabase.from('club_posts').delete().eq('id', postId);
  }

  Future<List<ClubPostComment>> postComments(String postId) async {
    final rows = await supabase
        .from('club_post_comments')
        .select('*, users!author_id(name)')
        .eq('post_id', postId)
        .order('created_at');
    return rows.map((r) => ClubPostComment.fromJson(r)).toList();
  }

  Future<ClubPostComment> addComment({
    required String postId,
    required String body,
  }) async {
    final userId = supabase.auth.currentUser!.id;
    final row = await supabase
        .from('club_post_comments')
        .insert({
          'post_id': postId,
          'author_id': userId,
          'body': body,
        })
        .select('*, users!author_id(name)')
        .single();
    return ClubPostComment.fromJson(row);
  }

  Future<void> deleteComment(String commentId) async {
    await supabase.from('club_post_comments').delete().eq('id', commentId);
  }

  Future<String> uploadPostImage({
    required String clubId,
    required Uint8List bytes,
    required String extension,
    required String contentType,
  }) async {
    final userId = supabase.auth.currentUser!.id;
    final path = '$userId/${DateTime.now().millisecondsSinceEpoch}.$extension';
    await supabase.storage.from('club-posts').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    return supabase.storage.from('club-posts').getPublicUrl(path);
  }
}
