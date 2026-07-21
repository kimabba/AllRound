import '../models/tournament.dart';
import 'api_base.dart';

/// 유저 프로필·종목·협회·지역 API.
mixin UserApi on ApiBase {
  /// 프로필 저장. 실명(name)은 대회·클럽용, 닉네임(nickname)은 앱 활동용,
  /// 생년월일(birth_date)은 연령·합산나이 대회 자격 매칭 내부용.
  Future<void> saveProfile({
    required String name,
    String? nickname,
    required DateTime birthDate,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Not authenticated');

    final trimmedNickname = nickname?.trim();
    await supabase.rpc('ensure_profile');
    await supabase.from('users').update({
      'name': name,
      'nickname':
          trimmedNickname == null || trimmedNickname.isEmpty ? null : trimmedNickname,
      // date 컬럼: 'YYYY-MM-DD' 형식 (시간대 영향 없음).
      'birth_date':
          birthDate.toIso8601String().split('T').first,
    }).eq('id', userId);
  }

  /// 본인 프로필(실명·닉네임·생년월일). row 없으면 null.
  Future<UserProfile?> myProfile() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return null;
    final row = await supabase
        .from('users')
        .select('name, nickname, birth_date, primary_region, interest_regions')
        .eq('id', userId)
        .maybeSingle();
    return row == null ? null : UserProfile.fromJson(row);
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
    await supabase.from('user_sports').delete().eq('user_id', userId);
    if (sports.isNotEmpty) {
      await supabase
          .from('user_sports')
          .insert(sports.map((s) => s.toInsert(userId)).toList());
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
