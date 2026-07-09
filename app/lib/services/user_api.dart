import '../models/tournament.dart';
import 'api_base.dart';

/// 유저 프로필·종목·협회·지역 API.
mixin UserApi on ApiBase {
  Future<void> saveDisplayName(String displayName) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Not authenticated');

    await supabase.rpc('ensure_profile');
    await supabase
        .from('users')
        .update({'name': displayName}).eq('id', userId);
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
