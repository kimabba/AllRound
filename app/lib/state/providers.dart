import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/tournament.dart';
import '../services/api.dart';

final supabaseProvider = Provider<SupabaseClient>((_) {
  return Supabase.instance.client;
});

final apiProvider = Provider<ApiService>((ref) {
  return ApiService(ref.watch(supabaseProvider));
});

/// 인증 상태 (Session 또는 null)
final authStateProvider = StreamProvider<AuthState>((ref) {
  final supa = ref.watch(supabaseProvider);
  return supa.auth.onAuthStateChange;
});

final currentUserProvider = Provider<User?>((ref) {
  // authStateProvider 를 watch 해야 onAuthStateChange 시 재평가됨.
  // (이 줄 없으면 supabaseProvider 인스턴스가 안 바뀌어 currentUser 가 stale 상태로 고정 →
  //  영속 세션 복원 실패한 첫 실행에서 로그인해도 화면이 안 바뀌는 버그)
  ref.watch(authStateProvider);
  return ref.watch(supabaseProvider).auth.currentUser;
});

/// 사용자 종목·등급 목록
final userSportsProvider = FutureProvider<List<UserSport>>((ref) async {
  // auth state 변경에 따라 invalidate
  ref.watch(authStateProvider);
  final api = ref.watch(apiProvider);
  return api.myUserSports();
});

/// 사용자 등록 협회 (multi-org) — 테니스 한정
final userTennisOrgsProvider = FutureProvider<List<UserTennisOrg>>((ref) async {
  ref.watch(authStateProvider);
  final api = ref.watch(apiProvider);
  return api.myTennisOrgs();
});

/// 사용자가 가입했거나 생성한 클럽 목록
final myClubsProvider = FutureProvider<List<Club>>((ref) async {
  ref.watch(authStateProvider);
  final api = ref.watch(apiProvider);
  return api.myClubs();
});

/// 권역 목록 (regions 테이블 — 8개 시드)
final regionsProvider = FutureProvider<List<Region>>((ref) async {
  ref.watch(authStateProvider);
  final api = ref.watch(apiProvider);
  return api.listRegions();
});

/// 즐겨찾기 ID 집합
final favoriteIdsProvider = FutureProvider<Set<String>>((ref) async {
  ref.watch(authStateProvider);
  final api = ref.watch(apiProvider);
  return api.myFavoriteIds();
});

/// 관심 클럽 ID 집합
final clubFavoriteIdsProvider = FutureProvider<Set<String>>((ref) async {
  ref.watch(authStateProvider);
  final api = ref.watch(apiProvider);
  return api.myClubFavoriteIds();
});

/// MY 페이지용 관심/예정 대회 기록
final myTournamentRecordsProvider =
    FutureProvider<List<Tournament>>((ref) async {
  ref.watch(authStateProvider);
  final api = ref.watch(apiProvider);
  return api
      .myFavoriteTournaments(limit: 5)
      .timeout(const Duration(seconds: 2));
});

/// 관심 화면용 스크랩 대회
final myFavoriteTournamentsProvider =
    FutureProvider<List<Tournament>>((ref) async {
  ref.watch(authStateProvider);
  final api = ref.watch(apiProvider);
  return api.myFavoriteTournaments(limit: 50);
});

/// 관심 화면용 스크랩 클럽
final myFavoriteClubsProvider = FutureProvider<List<Club>>((ref) async {
  ref.watch(authStateProvider);
  final api = ref.watch(apiProvider);
  return api.myFavoriteClubs(limit: 50);
});

String? primarySportFrom(List<UserSport> sports) {
  if (sports.isEmpty) return null;
  return sports.where((s) => s.isPrimary).firstOrNull?.sport ??
      sports.first.sport;
}

/// 사용자의 active 종목 — 앱 전체 필터 기준.
/// 프로필의 주 종목을 사용한다.
final activeSportProvider = Provider<String?>((ref) {
  final sports = ref.watch(userSportsProvider).valueOrNull ?? [];
  return primarySportFrom(sports);
});

/// 홈 자동 필터 결과 (activeSportProvider 기반)
final homeTournamentsProvider = FutureProvider<List<Tournament>>((ref) async {
  ref.watch(authStateProvider);
  final api = ref.watch(apiProvider);
  final sport = ref.watch(activeSportProvider);
  return api.searchTournaments(sport: sport, onlyMyGrade: true, limit: 50);
});

/// public.users.role 을 읽어 어드민 여부 반환.
/// currentUserProvider 변경 시 자동 재계산.
final isAdminProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return false;
  final supabase = ref.watch(supabaseProvider);
  final row = await supabase
      .from('users')
      .select('role')
      .eq('id', user.id)
      .maybeSingle();
  return row?['role'] == 'admin';
});

/// 관리자 룰 목록 (종목 필터, null=전체). 작업 후 invalidate 로 새로고침.
final adminRulesProvider =
    FutureProvider.autoDispose.family<List<RuleArticle>, String?>((ref, sport) {
  return ref.watch(apiProvider).adminListRules(sport: sport);
});

final unreadNotificationCountProvider = FutureProvider<int>((ref) async {
  final api = ref.watch(apiProvider);
  return api.unreadNotificationCount();
});
