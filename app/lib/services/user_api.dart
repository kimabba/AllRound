import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/tournament.dart';
import 'api_base.dart';

String _profileImageExtension(String extension, String contentType) {
  final normalized = extension.toLowerCase().replaceAll('jpeg', 'jpg');
  final expected = switch (normalized) {
    'jpg' => 'image/jpeg',
    'png' => 'image/png',
    _ => null,
  };
  if (expected == null || contentType != expected) {
    throw const FormatException('Invalid sanitized profile image format');
  }
  return normalized;
}

/// 유저 프로필·종목·협회·지역 API.
mixin UserApi on ApiBase {
  /// 프로필 저장. 실명(name)은 대회·클럽용, 닉네임(nickname)은 앱 활동용,
  /// 생년월일(birth_date)은 연령·합산나이 대회 자격 매칭 내부용.
  /// 활동 지역(primary_region)은 유저 지역의 **단일 진실원천**이다.
  /// (협회 등록 여부와 무관하게 여기에 저장한다. user_tennis_orgs.region_code 는 deprecated)
  Future<void> saveProfile({
    required String name,
    String? nickname,
    required DateTime birthDate,
    String? primaryRegion,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Not authenticated');

    final trimmedNickname = nickname?.trim();
    await supabase.rpc('ensure_profile');
    await supabase.from('users').update({
      'name': name,
      'nickname': trimmedNickname == null || trimmedNickname.isEmpty
          ? null
          : trimmedNickname,
      // date 컬럼: 'YYYY-MM-DD' 형식 (시간대 영향 없음).
      'birth_date': birthDate.toIso8601String().split('T').first,
      // null 은 "이번 저장에서 지역을 다루지 않음" → 기존 값 보존.
      if (primaryRegion != null) 'primary_region': primaryRegion,
    }).eq('id', userId);
  }

  /// 본인 프로필(실명·닉네임·생년월일). row 없으면 null.
  Future<UserProfile?> myProfile() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return null;
    final row = await supabase
        .from('users')
        .select('name, nickname, birth_date, primary_region, avatar_url')
        .eq('id', userId)
        .maybeSingle();
    return row == null ? null : UserProfile.fromJson(row);
  }

  Future<String> uploadProfileAvatar({
    required Uint8List bytes,
    required String extension,
    required String contentType,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Not authenticated');
    final ext = _profileImageExtension(extension, contentType);
    final path = '$userId/avatar.$ext';
    await supabase.storage.from('profile-avatars').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    final publicUrl =
        supabase.storage.from('profile-avatars').getPublicUrl(path);
    final versionedUrl =
        '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
    await supabase.from('users').update({'avatar_url': versionedUrl}).eq(
      'id',
      userId,
    );
    return versionedUrl;
  }

  Future<void> removeProfileAvatar() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Not authenticated');
    await supabase.storage.from('profile-avatars').remove([
      '$userId/avatar.jpg',
      '$userId/avatar.png',
    ]);
    await supabase.from('users').update({'avatar_url': null}).eq('id', userId);
  }

  Future<List<UserSport>> myUserSports() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];
    final rows = await supabase
        .from('user_sports')
        .select()
        .eq('user_id', userId)
        .order('is_primary', ascending: false);
    return rows.map((r) => UserSport.fromJson(r)).toList();
  }

  Future<void> saveUserSports(List<UserSport> sports) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Not authenticated');

    await supabase.rpc('ensure_profile');
    // 전체 삭제 후 재삽입하면 DELETE 와 INSERT 가 별도 트랜잭션이라, INSERT 가 거부될 때
    // (폐기 등급 보유자 등) 종목 정보가 통째로 사라진다. 제거된 종목만 지우고 나머지는
    // upsert 해서, 실패해도 기존 행이 남게 한다.
    final keep = sports.map((s) => s.sport).toList();
    final removed = supabase.from('user_sports').delete().eq('user_id', userId);
    await (keep.isEmpty
        ? removed
        : removed.not('sport', 'in', '(${keep.join(',')})'));
    if (sports.isNotEmpty) {
      await supabase.from('user_sports').upsert(
            sports.map((s) => s.toInsert(userId)).toList(),
            onConflict: 'user_id,sport',
          );
    }
  }

  Future<List<Region>> listRegions() async {
    final rows = await supabase.from('regions').select().order('code');
    return rows.map((r) => Region.fromJson(r)).toList();
  }

  Future<List<UserTennisOrg>> myTennisOrgs() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];
    final rows = await supabase
        .from('user_tennis_orgs')
        .select()
        .eq('user_id', userId)
        .order('is_primary', ascending: false);
    return rows.map((r) => UserTennisOrg.fromJson(r)).toList();
  }

  Future<void> saveTennisOrgs(List<UserTennisOrg> orgs) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Not authenticated');

    await supabase.from('user_tennis_orgs').delete().eq('user_id', userId);
    if (orgs.isNotEmpty) {
      await supabase
          .from('user_tennis_orgs')
          .insert(orgs.map((o) => o.toUpsert(userId)).toList());
    }
  }

  Future<void> upsertTennisOrg(UserTennisOrg org) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Not authenticated');
    await supabase.from('user_tennis_orgs').upsert(org.toUpsert(userId));
  }

  Future<void> deleteTennisOrg(String org, String division) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    await supabase
        .from('user_tennis_orgs')
        .delete()
        .eq('user_id', userId)
        .eq('org', org)
        .eq('division', division);
  }

  /// 회원 탈퇴. 개인 데이터는 삭제, 작성 콘텐츠는 익명화(delete-account Edge Function).
  /// 성공 후 호출 측에서 signOut 해야 한다.
  Future<void> deleteAccount() async {
    final headers = await authHeaders();
    final res = await httpPost(uri('delete-account'), headers: headers);
    check(res);
  }
}
