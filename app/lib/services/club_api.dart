import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/club_event.dart';
import '../models/club_chat.dart';
import '../models/club_dues.dart';
import '../models/club_inquiry.dart';
import '../models/club_post.dart';
import '../models/club_recruiting.dart';
import '../models/place_search_result.dart';
import '../models/tournament.dart';
import '../models/venue.dart';
import '../utils/grade_labels.dart';
import '../utils/storage_object_name.dart';
import 'api_base.dart';

String _verifiedImageExtension(String extension, String contentType) {
  final normalized = extension.toLowerCase().replaceAll('jpeg', 'jpg');
  final expectedContentType = switch (normalized) {
    'jpg' => 'image/jpeg',
    'png' => 'image/png',
    _ => null,
  };
  if (expectedContentType == null || contentType != expectedContentType) {
    throw const FormatException('Invalid sanitized image format');
  }
  return normalized;
}

/// 모임 CRUD·가입·멤버·이벤트·게시판·즐겨찾기 API.
mixin ClubApi on ApiBase {
  // ── 검색 / 생성 ──────────────────────────────────────────────

  Future<List<Club>> searchClubs(
      {String? sport,
      String? region,
      String? q,
      double? latitude,
      double? longitude,
      double? radiusKm}) async {
    final res = await httpGet(
      uri('clubs-search', {
        if (sport != null) 'sport': sport,
        if (region != null) 'region': region,
        if (q != null && q.isNotEmpty) 'q': q,
        if (latitude != null) 'latitude': latitude.toString(),
        if (longitude != null) 'longitude': longitude.toString(),
        if (radiusKm != null) 'radius_km': radiusKm.toString(),
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
    final res = await httpGet(
      uri('clubs-search', {'mine': 'true'}),
      headers: await authHeaders(),
    );
    check(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['clubs'] as List)
        .map((e) => Club.fromJson(e as Map<String, dynamic>))
        // 구버전 Edge Function이 생성자 조건으로 소프트 삭제된 클럽까지
        // 반환하더라도 앱의 모든 "내 클럽" 화면에서 다시 노출하지 않는다.
        .where((club) => !club.isDeletedByOwner)
        .toList();
  }

  /// 내 pending 가입 신청 모임(승인 대기중). 활성 멤버십과 별개 목록.
  Future<List<Club>> myPendingJoinRequests() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return const [];
    final rows = await supabase
        .from('club_join_requests')
        .select('clubs!inner(*)')
        .eq('user_id', uid)
        .eq('status', 'pending');
    return (rows as List)
        .whereType<Map>()
        .map((r) => r['clubs'])
        .whereType<Map>()
        .map((c) => Club.fromJson(Map<String, dynamic>.from(c)))
        .toList();
  }

  Future<List<Venue>> searchVenues({
    String? sport,
    String? region,
    String? query,
    int limit = 30,
  }) async {
    final res = await supabase.rpc(
      'venues_search',
      params: {
        'p_sport': sport,
        'p_region': region,
        'p_query': query == null || query.trim().isEmpty ? null : query.trim(),
        'p_limit': limit,
      },
    );
    if (res is! List) return const [];
    return res
        .whereType<Map>()
        .map((row) => Venue.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<PlaceSearchResult>> searchPlaces(String query) async {
    final normalized = query.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length < 2) return const [];
    final res = await httpGet(
      uri('place-search', {'q': normalized}),
      headers: await authHeaders(),
    );
    check(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final places = body['places'];
    if (places is! List) return const [];
    return places
        .whereType<Map>()
        .map((place) => PlaceSearchResult.fromJson(
              Map<String, dynamic>.from(place),
            ))
        .toList(growable: false);
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
    List<String> introImageUrls = const [],
    List<String>? meetingDays,
    int? monthlyFee,
    String feeType = 'monthly',
    String? genderPreference,
    String cardColor = '#3156D8',
    double? latitude,
    double? longitude,
  }) async {
    final res = await httpPost(
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
        if (introImageUrls.isNotEmpty) 'intro_image_urls': introImageUrls,
        if (meetingDays != null && meetingDays.isNotEmpty)
          'meeting_days': meetingDays,
        if (monthlyFee != null) 'monthly_fee': monthlyFee,
        'fee_type': feeType,
        if (genderPreference != null && genderPreference.isNotEmpty)
          'gender_preference': genderPreference,
        'card_color': cardColor,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
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

    final ext = _verifiedImageExtension(extension, contentType);
    // 구형 폴더 기반 정책과 현재 owner_id 정책에서 모두 업로드되도록
    // 사용자 폴더를 유지한다. 공개 URL에는 불투명 파일명만 추가로 노출된다.
    final path = '$userId/${newOpaqueImageObjectName(ext)}';

    await supabase.storage.from('club-logos').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: false,
          ),
        );
    return supabase.storage.from('club-logos').getPublicUrl(path);
  }

  Future<String> uploadClubIntroImage({
    required Uint8List bytes,
    required String extension,
    required String contentType,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Not authenticated');

    final ext = _verifiedImageExtension(extension, contentType);
    final path = '$userId/${newOpaqueImageObjectName(ext)}';

    await supabase.storage.from('club-intro-images').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: false,
          ),
        );
    return supabase.storage.from('club-intro-images').getPublicUrl(path);
  }

  /// 단일 모임 상세 조회 (딥링크 등 ID만 있을 때 사용).
  Future<Club> getClub(String clubId) async {
    final uid = supabase.auth.currentUser?.id;
    var query = supabase.from('clubs').select(
          '*, club_members!left(role, status, can_post_notice)',
        );
    if (uid != null) {
      query = query.eq('club_members.user_id', uid);
    }
    final row = await query.eq('id', clubId).single();
    return Club.fromJson(row);
  }

  // ── 팀원 모집 ──────────────────────────────────────────────

  Future<List<RecruitingPostPreview>> teamRecruitingPosts(
      {List<String>? regions, String? sport, int limit = 50}) async {
    var query = supabase
        .from('club_recruiting_posts')
        .select(
          '*, clubs!inner(id, name, sport, region, status)',
        )
        .eq('clubs.status', 'approved');
    if (sport != null && sport.isNotEmpty) {
      query = query.eq('clubs.sport', sport);
    }
    if (regions != null && regions.isNotEmpty) {
      query = query.inFilter('clubs.region', regions);
    }
    final Object raw =
        await query.order('created_at', ascending: false).limit(limit);
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (row) => RecruitingPostPreview.fromJson(
            Map<String, dynamic>.from(row),
          ),
        )
        .toList(growable: false);
  }

  Future<RecruitingPostPreview> createTeamRecruitingPost({
    required String clubId,
    required Sport sport,
    required String title,
    required String place,
    required String schedule,
    required List<String> skillLevels,
    required String gender,
    required List<String> ages,
    required int fieldCount,
    required int keeperCount,
    required int totalCount,
    String? position,
    String? intro,
    String cost = '협의',
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Not authenticated');
    // skill_level 은 free-text 라 DB 가 길이만 검사한다. 등급 정본에서 파생된
    // 선택지 밖의 값(폐기된 부수체계 등)이 새로 유입되면 여기서 막는다(JY-146).
    // assert 가 아니라 예외인 이유: assert 는 릴리스 빌드에서 제거돼 정작 운영에서
    // 무력해지고, 디버그와 릴리스의 동작이 갈린다. 이 앱을 거치지 않는 경로(PostgREST
    // 직접 호출)는 여전히 열려 있다 — 근본 차단은 P3 의 데이터 정규화 후 DB 제약.
    if (skillLevels.isEmpty ||
        skillLevels.any((level) => !isAllowedSkillLevelLabel(sport, level)) ||
        (skillLevels.length > 1 && skillLevels.contains(anyGradeLabel))) {
      throw ArgumentError.value(
        skillLevels,
        'skillLevels',
        '${sportLabel(sport)} 등급 정본에 없는 값',
      );
    }
    if (ages.isEmpty || (ages.length > 1 && ages.contains('무관'))) {
      throw ArgumentError.value(ages, 'ages', '연령 선택이 올바르지 않음');
    }

    final Object raw = await supabase
        .from('club_recruiting_posts')
        .insert({
          'club_id': clubId,
          'created_by': userId,
          'title': title.trim(),
          'place': place.trim(),
          'schedule_text': schedule.trim(),
          'skill_level': skillLevels.join(' · '),
          'gender_text': gender,
          'age_text': ages.join(' · '),
          'position_text': position,
          'field_count': fieldCount,
          'keeper_count': keeperCount,
          'total_count': totalCount,
          'cost_text': cost.trim().isEmpty ? '협의' : cost.trim(),
          if (intro?.trim().isNotEmpty == true) 'intro': intro!.trim(),
        })
        .select('*, clubs!inner(id, name, sport, region, status)')
        .single();
    if (raw is! Map) throw const FormatException('Invalid recruiting post');
    return RecruitingPostPreview.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<void> closeTeamRecruitingPost(String postId) async {
    await supabase.from('club_recruiting_posts').update({
      'status': 'closed',
      'closed_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', postId);
  }

  // ── 가입 / 탈퇴 ──────────────────────────────────────────────

  Future<ClubInquiryThread?> myClubInquiry(String clubId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return null;
    final Object? raw = await supabase
        .from('club_inquiry_threads')
        .select(
          'id, club_id, requester_id, status, last_message_at, created_at',
        )
        .eq('club_id', clubId)
        .eq('requester_id', userId)
        .maybeSingle();
    if (raw is! Map) return null;
    return ClubInquiryThread.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<List<ClubInquiryThread>> managedClubInquiries(String clubId) async {
    final response = await httpGet(
      uri('clubs-inquiries', {'club_id': clubId}),
      headers: await authHeaders(),
    );
    check(response);
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map) return const [];
    final Object? raw = decoded['threads'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (row) => ClubInquiryThread.fromJson(
            Map<String, dynamic>.from(row),
          ),
        )
        .toList(growable: false);
  }

  Future<List<ClubInquiryMessage>> clubInquiryMessages(
    String threadId,
  ) async {
    final Object raw = await supabase
        .from('club_inquiry_messages')
        .select('id, thread_id, sender_id, body, created_at')
        .eq('thread_id', threadId)
        .order('created_at');
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (row) => ClubInquiryMessage.fromJson(
            Map<String, dynamic>.from(row),
          ),
        )
        .toList(growable: false);
  }

  Future<String> sendClubInquiry({
    String? clubId,
    String? threadId,
    required String body,
  }) async {
    final response = await httpPost(
      uri('clubs-inquiries'),
      headers: await authHeaders(),
      body: jsonEncode({
        if (clubId != null) 'club_id': clubId,
        if (threadId != null) 'thread_id': threadId,
        'body': body.trim(),
      }),
    );
    check(response);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['thread_id'] as String;
  }

  Future<void> joinClub(String clubId, {String? message}) async {
    final res = await httpPost(
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
    final res = await httpPost(
      uri('clubs-join'),
      headers: await authHeaders(),
      body: jsonEncode({'club_id': clubId, 'action': 'cancel'}),
    );
    check(res);
  }

  Future<MyClubJoinRequest?> myPendingClubJoinRequest(String clubId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return null;

    final Object? raw = await supabase
        .from('club_join_requests')
        .select('id, status, created_at')
        .eq('club_id', clubId)
        .eq('user_id', userId)
        .eq('status', 'pending')
        .maybeSingle();
    if (raw is! Map) return null;
    return MyClubJoinRequest.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<void> leaveClub(String clubId) async {
    final res = await httpPost(
      uri('clubs-join'),
      headers: await authHeaders(),
      body: jsonEncode({'club_id': clubId, 'action': 'leave'}),
    );
    check(res);
  }

  Future<void> kickMember(String clubId, String targetUserId) async {
    final res = await httpPost(
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

  Future<void> banClubMember(String clubId, String targetUserId) async {
    final res = await httpPost(
      uri('clubs-join'),
      headers: await authHeaders(),
      body: jsonEncode({
        'club_id': clubId,
        'action': 'ban',
        'target_user_id': targetUserId,
      }),
    );
    check(res);
  }

  Future<void> setClubMemberRole({
    required String clubId,
    required String targetUserId,
    required String role,
  }) async {
    final res = await httpPost(
      uri('clubs-join'),
      headers: await authHeaders(),
      body: jsonEncode({
        'club_id': clubId,
        'action': 'set_manager',
        'target_user_id': targetUserId,
        'role': role,
      }),
    );
    check(res);
  }

  Future<void> updateClubMonthlyFee(String clubId, int? monthlyFee) async {
    final res = await httpPost(
      uri('clubs-join'),
      headers: await authHeaders(),
      body: jsonEncode({
        'club_id': clubId,
        'action': 'update_monthly_fee',
        'monthly_fee': monthlyFee,
      }),
    );
    check(res);
  }

  Future<void> updateClubIntro({
    required String clubId,
    required String? description,
    required List<String> introImageUrls,
  }) async {
    final res = await httpPost(
      uri('clubs-join'),
      headers: await authHeaders(),
      body: jsonEncode({
        'club_id': clubId,
        'action': 'update_intro',
        'description': description,
        'intro_image_urls': introImageUrls,
      }),
    );
    check(res);
  }

  Future<void> resubmitClubReview(String clubId) async {
    final res = await httpPost(
      uri('clubs-join'),
      headers: await authHeaders(),
      body: jsonEncode({
        'club_id': clubId,
        'action': 'resubmit_review',
      }),
    );
    check(res);
  }

  Future<void> deleteClub(String clubId) async {
    final res = await httpPost(
      uri('clubs-join'),
      headers: await authHeaders(),
      body: jsonEncode({
        'club_id': clubId,
        'action': 'delete_club',
      }),
    );
    check(res);
  }

  Future<List<Map<String, dynamic>>> pendingJoinRequests(String clubId) async {
    final response = await httpGet(
      uri('clubs-review-join', {'club_id': clubId}),
      headers: await authHeaders(),
    );
    check(response);
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map) return const [];
    final Object? raw = decoded['requests'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<void> reviewJoinRequest(String requestId,
      {required bool approve, String? reason}) async {
    final res = await httpPost(
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
    final res = await httpPost(
      uri('clubs-join'),
      headers: await authHeaders(),
      body: jsonEncode({
        'club_id': clubId,
        'action': 'list_members',
      }),
    );
    check(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final rows = (body['members'] as List? ?? const []);
    final members = rows
        .whereType<Map>()
        .map((row) => ClubMember.fromJson(Map<String, dynamic>.from(row)))
        .toList();
    members.sort((a, b) {
      if (a.joinedAt == null) return b.joinedAt == null ? 0 : 1;
      if (b.joinedAt == null) return -1;
      return a.joinedAt!.compareTo(b.joinedAt!);
    });
    return members;
  }

  Future<List<ClubDuesPeriod>> clubDuesPeriods(String clubId) async {
    final rows = await supabase
        .from('club_dues_periods')
        .select()
        .eq('club_id', clubId)
        .order('period_month', ascending: false);
    return (rows as List)
        .whereType<Map>()
        .map((row) => ClubDuesPeriod.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<ClubDuesPayment>> clubDuesPayments(String periodId) async {
    final rows = await supabase
        .from('club_dues_payments')
        .select()
        .eq('period_id', periodId)
        .order('updated_at', ascending: false);
    return (rows as List)
        .whereType<Map>()
        .map((row) => ClubDuesPayment.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<ClubDuesAuditEntry>> clubDuesAudit(
    Iterable<String> paymentIds,
  ) async {
    final ids = paymentIds.toList(growable: false);
    if (ids.isEmpty) return const [];
    final rows = await supabase
        .from('club_dues_audit')
        .select()
        .inFilter('payment_id', ids)
        .order('created_at', ascending: false)
        .limit(100);
    return (rows as List)
        .whereType<Map>()
        .map((row) =>
            ClubDuesAuditEntry.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<String> upsertClubDuesPeriod({
    required String clubId,
    required DateTime periodMonth,
    required int amount,
    DateTime? dueDate,
    String? accountInfo,
  }) async {
    final result = await supabase.rpc(
      'upsert_club_dues_period',
      params: {
        'p_club_id': clubId,
        'p_period_month':
            DateTime(periodMonth.year, periodMonth.month).toIso8601String(),
        'p_amount': amount,
        'p_due_date': dueDate == null
            ? null
            : DateTime(dueDate.year, dueDate.month, dueDate.day)
                .toIso8601String(),
        'p_account_info': accountInfo,
      },
    );
    if (result is! String) {
      throw const FormatException('회비 장부 저장 결과가 올바르지 않습니다.');
    }
    return result;
  }

  Future<int> setClubDueStatus({
    required String periodId,
    required Iterable<String> userIds,
    required ClubDueStatus status,
    String? note,
  }) async {
    final result = await supabase.rpc(
      'set_club_due_status',
      params: {
        'p_period_id': periodId,
        'p_user_ids': userIds.toList(growable: false),
        'p_status': status.value,
        'p_note': note,
      },
    );
    return (result as num).toInt();
  }

  Future<int> sendClubDuesReminders({
    required String periodId,
    required Iterable<String> userIds,
  }) async {
    final result = await supabase.rpc(
      'send_club_dues_reminders',
      params: {
        'p_period_id': periodId,
        'p_user_ids': userIds.toList(growable: false),
      },
    );
    return (result as num).toInt();
  }

  Future<List<ClubMember>> formerClubMembers(String clubId) async {
    final res = await httpPost(
      uri('clubs-join'),
      headers: await authHeaders(),
      body: jsonEncode({
        'club_id': clubId,
        'action': 'list_former_members',
      }),
    );
    check(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final rows = body['members'] as List? ?? const [];
    return rows
        .whereType<Map>()
        .map((row) => ClubMember.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
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

  Future<void> endClubEvent(String clubId, String eventId) async {
    await _manageClubEvent(clubId, eventId, 'end');
  }

  Future<void> deleteClubEvent(String clubId, String eventId) async {
    await _manageClubEvent(clubId, eventId, 'delete');
  }

  Future<void> _manageClubEvent(
    String clubId,
    String eventId,
    String action,
  ) async {
    final response = await httpPost(
      uri('clubs-events'),
      headers: await authHeaders(),
      body: jsonEncode({
        'action': action,
        'club_id': clubId,
        'event_id': eventId,
      }),
    );
    check(response);
  }

  Future<void> createClubEvent({
    required String clubId,
    required String title,
    String? description,
    String? locationText,
    required DateTime startsAt,
    int? fee,
    int? capacity,
    String? repeatInterval,
  }) async {
    if (supabase.auth.currentUser == null) {
      throw StateError('Not authenticated');
    }
    final response = await httpPost(
      uri('clubs-events'),
      headers: await authHeaders(),
      body: jsonEncode({
        'club_id': clubId,
        'title': title,
        if (description != null && description.isNotEmpty)
          'description': description,
        if (locationText != null && locationText.isNotEmpty)
          'location_text': locationText,
        'starts_at': startsAt.toUtc().toIso8601String(),
        if (fee != null) 'fee': fee,
        if (capacity != null) 'capacity': capacity,
        if (repeatInterval != null) 'repeat_interval': repeatInterval,
      }),
    );
    check(response);
  }

  Future<void> respondEvent(String eventId, {required bool going}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) throw StateError('Not authenticated');
    await supabase.rpc('respond_club_event', params: {
      'p_event_id': eventId,
      'p_status': going ? 'going' : 'not_going',
    });
  }

  Future<String> openClubChat({
    required String clubId,
    String? otherUserId,
  }) async {
    final result = await supabase.rpc('open_club_chat', params: {
      'p_club_id': clubId,
      'p_other_user_id': otherUserId,
    });
    if (result is! String) {
      throw const FormatException('대화방 정보를 확인하지 못했습니다.');
    }
    return result;
  }

  Future<List<ClubChatMessage>> clubChatMessages(String threadId) async {
    final rows = await supabase
        .from('club_chat_messages')
        .select('id, thread_id, sender_id, body, created_at')
        .eq('thread_id', threadId)
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(300);
    final messages = (rows as List)
        .whereType<Map>()
        .map((row) => ClubChatMessage.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
    return messages.reversed.toList(growable: false);
  }

  Stream<List<ClubChatMessage>> watchClubChatMessages(String threadId) {
    return supabase
        .from('club_chat_messages')
        .stream(primaryKey: ['id'])
        .eq('thread_id', threadId)
        .order('created_at', ascending: false)
        .limit(300)
        .map((rows) {
          final messages =
              rows.map(ClubChatMessage.fromJson).toList(growable: false);
          messages.sort((a, b) {
            final createdAtOrder = a.createdAt.compareTo(b.createdAt);
            return createdAtOrder != 0 ? createdAtOrder : a.id.compareTo(b.id);
          });
          return messages;
        });
  }

  Future<void> sendClubChatMessage({
    required String threadId,
    required String body,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Not authenticated');
    final text = body.trim();
    if (text.isEmpty || text.length > 1000) {
      throw const FormatException('메시지는 1자 이상 1,000자 이하로 입력해주세요.');
    }
    await supabase.from('club_chat_messages').insert({
      'thread_id': threadId,
      'sender_id': userId,
      'body': text,
    });
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

  Future<List<ClubPost>> clubPosts(
    String clubId, {
    String? tag,
    String? authorQuery,
  }) async {
    final normalizedAuthor = authorQuery?.trim();
    final searchingAuthor =
        normalizedAuthor != null && normalizedAuthor.isNotEmpty;
    var query = supabase
        .from('club_posts')
        .select(
          searchingAuthor
              ? '*, users!inner(name), club_post_comments(id)'
              : '*, users!author_id(name), club_post_comments(id)',
        )
        .eq('club_id', clubId);
    if (tag != null && tag != 'notice') {
      query = query.or(
        'tag.eq.$tag,and(tag.eq.notice,notice_visible_tags.cs.{$tag})',
      );
    } else if (tag == 'notice') {
      query = query.eq('tag', tag!);
    }
    if (searchingAuthor) {
      query = query.ilike('users.name', '%$normalizedAuthor%');
    }
    final rows = await query.order('created_at', ascending: false).limit(50);
    final posts = rows.map((r) => ClubPost.fromJson(r)).toList();
    posts.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return posts;
  }

  Future<ClubPost> createPost({
    required String clubId,
    required String tag,
    required String title,
    required String body,
    bool isPinned = false,
    List<String> imageUrls = const [],
    List<String> noticeVisibleTags = const [],
  }) async {
    final userId = supabase.auth.currentUser!.id;
    final payload = <String, Object>{
      'club_id': clubId,
      'author_id': userId,
      'tag': tag,
      'title': title,
      'body': body,
      'image_urls': imageUrls,
      'notice_visible_tags': noticeVisibleTags,
    };
    if (isPinned) payload['is_pinned'] = true;
    final row = await supabase
        .from('club_posts')
        .insert(payload)
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
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Not authenticated');
    final row = await supabase
        .from('club_post_comments')
        .insert({
          'post_id': postId,
          'author_id': userId,
          'body': body.trim(),
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
    if (supabase.auth.currentUser == null) {
      throw StateError('Not authenticated');
    }
    final ext = _verifiedImageExtension(extension, contentType);
    final path = newOpaqueImageObjectName(ext);
    await supabase.storage.from('club-posts').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
    return supabase.storage.from('club-posts').getPublicUrl(path);
  }
}
