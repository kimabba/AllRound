import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/club_recruiting.dart';
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

/// 비밀번호 재설정 진행 상태. passwordRecovery 딥링크 진입 시 sticky 하게 true 가
/// 되고, 새 비번 저장 성공 시 화면이 complete() 로 끈다. auth 이벤트의 최신값에
/// 의존하면 updateUser 직후 userUpdated 관측 전 race 로 recovery 판정이 튀므로,
/// 명시적 플래그로 고정한다.
class RecoveryModeNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref.listen(authStateProvider, (_, next) {
      final event = next.valueOrNull?.event;
      if (event == AuthChangeEvent.passwordRecovery) {
        state = true;
      } else if (event == AuthChangeEvent.userUpdated ||
          event == AuthChangeEvent.signedOut) {
        // 비번 저장 성공(userUpdated) 또는 로그아웃 시 자동 해제. 위젯이 unmount
        // 되어 complete() 를 못 불러도, 이전 사용자의 true 가 남지 않게 한다.
        state = false;
      }
    });
    // 콜드스타트 딥링크: listen 등록 전 이미 도착한 이벤트도 반영.
    return ref.read(authStateProvider).valueOrNull?.event ==
        AuthChangeEvent.passwordRecovery;
  }

  /// 저장 성공 직후 즉시 해제(context.go 전에 호출 → redirect 되돌림 race 제거).
  void complete() => state = false;
}

final recoveryModeProvider =
    NotifierProvider<RecoveryModeNotifier, bool>(RecoveryModeNotifier.new);

final currentUserProvider = Provider<User?>((ref) {
  // authStateProvider 를 watch 해야 onAuthStateChange 시 재평가됨.
  // (이 줄 없으면 supabaseProvider 인스턴스가 안 바뀌어 currentUser 가 stale 상태로 고정 →
  //  영속 세션 복원 실패한 첫 실행에서 로그인해도 화면이 안 바뀌는 버그)
  ref.watch(authStateProvider);
  return ref.watch(supabaseProvider).auth.currentUser;
});

/// 본인 프로필(실명·닉네임·생년월일)
final myProfileProvider = FutureProvider<UserProfile?>((ref) async {
  ref.watch(authStateProvider);
  final api = ref.watch(apiProvider);
  return api.myProfile();
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
  return api.myFavoriteTournaments(limit: null);
});

/// 관심 화면용 스크랩 클럽
final myFavoriteClubsProvider = FutureProvider<List<Club>>((ref) async {
  ref.watch(authStateProvider);
  final api = ref.watch(apiProvider);
  return api.myFavoriteClubs(limit: null);
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
  final sports = ref.watch(userSportsProvider).valueOrNull ?? const [];
  final tennisOrgs = ref.watch(userTennisOrgsProvider).valueOrNull ?? const [];
  // 등급·협회 등록이 하나도 없으면 자격 매칭이 전부 실패해 목록이 빈다.
  // 그 경우엔 전체 published 를 보여준다(등록이 있으면 내 등급 필터 유지).
  final hasGradeBasis = sports.isNotEmpty || tennisOrgs.isNotEmpty;
  final matched = await api.searchTournaments(
    sport: sport,
    onlyMyGrade: hasGradeBasis,
    limit: 50,
  );
  // 임시책(지역↔KATO 등급 대응표 완성 전): 내 등급 매칭 중 '다가오는' 대회가
  // 하나도 없으면 같은 종목 전체 대회로 fallback 해 추천이 비지 않게 한다.
  // 예) 광주 등급 유저에게 8월 KATO 전국대회가 등급 불일치로 전부 걸러지는 경우.
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final hasUpcoming = matched.any((t) => !t.startDate.isBefore(today));
  if (hasGradeBasis && !hasUpcoming) {
    try {
      return await api.searchTournaments(sport: sport, onlyMyGrade: false, limit: 50);
    } catch (_) {
      return matched; // fallback 조회 실패 시 1차 결과라도 보존 (codex P2)
    }
  }
  return matched;
});

/// 홈 노출용 팀원 모집글 — 모집중만, 풋살 우선, 상위 4개.
///
/// ponytail: 지역 필터는 아직 걸지 않는다(전국 노출). users.primary_region 은
/// 코드('gwangju')인데 clubs.region 은 한글 자유입력('광주'/'광주광역시', 경기
/// 광주시까지 혼재)이라 매칭이 성립하지 않는다. clubs.region 정합성 정리 후
/// 코드 기준 필터를 다시 건다 (Commander 결정 2026-07-21).
final homeRecruitingProvider =
    FutureProvider<List<RecruitingPostPreview>>((ref) async {
  ref.watch(authStateProvider);
  final api = ref.watch(apiProvider);
  final sport = ref.watch(activeSportProvider);
  final posts = await api.teamRecruitingPosts(sport: sport);
  return pickHomeRecruiting(posts);
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
