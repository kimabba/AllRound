import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/club_recruiting.dart';
import '../models/org_ranking.dart';
import '../models/org_ranking_snapshot.dart';
import '../models/player_result.dart';
import '../models/tournament.dart';
import '../services/api.dart';
import '../utils/grade_labels.dart';
import '../utils/kst.dart';

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
      final event = next.value?.event;
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
    return ref.read(authStateProvider).value?.event ==
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

/// 내 협회 전적(연결 승인된 경우에만 행이 온다)
final myPlayerResultsProvider = FutureProvider<List<PlayerResult>>((ref) async {
  ref.watch(authStateProvider);
  final api = ref.watch(apiProvider);
  return api.myPlayerResults();
});

/// 내 확정 연결 — 없으면 연결 유도를 띄운다
final myConfirmedLinkProvider =
    FutureProvider<Map<String, dynamic>?>((ref) async {
  ref.watch(authStateProvider);
  final api = ref.watch(apiProvider);
  return api.myConfirmedLink();
});

/// 연결된 내 현재 순위(부서별). 스펙 §7.2 블록 1 "지금".
final myCurrentRankingsProvider =
    FutureProvider<List<OrgRankingRow>>((ref) async {
  ref.watch(authStateProvider);
  final api = ref.watch(apiProvider);
  return api.myCurrentRankings();
});

/// 연결된 내 순위 추이. 여러 부서에 연결돼 있으면 첫 번째(myCurrentRankings
/// 순서 기준) 부서만 그린다 — 부서별로 나눠 그리는 건 이번 스코프 밖이다.
final myRankingHistoryProvider =
    FutureProvider<List<OrgRankingSnapshot>>((ref) async {
  ref.watch(authStateProvider);
  final rankings = await ref.watch(myCurrentRankingsProvider.future);
  if (rankings.isEmpty) return const [];
  final primary = rankings.first;
  final orgPlayerId = primary.orgPlayerId;
  if (orgPlayerId == null) return const [];
  final api = ref.watch(apiProvider);
  return api.playerRankingHistory(
    orgCode: primary.orgCode,
    divisionCode: primary.divisionCode,
    orgPlayerId: orgPlayerId,
  );
});

/// 홈 "내 등급 카드" 한 장에 필요한 값. 협회가 공표한 사실만 담는다.
/// [top10Points] 는 그 부서 10위의 점수(그 부서에 10명이 안 되면 null).
typedef MyGradeSummary = ({OrgRankingRow ranking, int? top10Points});

/// 여러 부서에 이름이 오른 사람의 대표 부서 한 줄. 협회가 랭킹표를 공표하는
/// 순서([kRankingDivisions])가 곧 상위→하위라 그 자리를 그대로 쓴다.
/// 목록에 없는 부서(미러 밖 협회)는 뒤로 민다.
OrgRankingRow? topDivisionRanking(List<OrgRankingRow> rows) {
  if (rows.isEmpty) return null;
  int tier(OrgRankingRow row) {
    final order = kRankingDivisions[row.orgCode];
    // 협회 자체가 목록에 없으면(미러 확장 과도기) 맨 뒤로 보낸다. order.length(0)를
    // 쓰면 목록에 있는 협회의 1순위 부서(tier 0)와 값이 같아져 잘못 앞서 뽑힌다.
    if (order == null) return 1 << 30;
    final index = order.indexOf(row.divisionCode);
    return index < 0 ? order.length : index;
  }

  final sorted = [...rows]..sort((a, b) {
      final byTier = tier(a).compareTo(tier(b));
      if (byTier != 0) return byTier;
      return a.divisionCode.compareTo(b.divisionCode);
    });
  return sorted.first;
}

/// 홈 최상단 등급 카드. 협회 연결이 없으면 null 이고 카드 자체가 안 뜬다.
final myGradeSummaryProvider = FutureProvider<MyGradeSummary?>((ref) async {
  ref.watch(authStateProvider);
  final top = topDivisionRanking(await ref.watch(myCurrentRankingsProvider.future));
  if (top == null) return null;
  final cutoff = await ref.watch(apiProvider).divisionRankRow(
        orgCode: top.orgCode,
        divisionCode: top.divisionCode,
        rank: 10,
      );
  return (ranking: top, top10Points: cutoff?.totalPoints);
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

/// 사용자가 화면에서 고른 종목. null 이면 프로필 주 종목을 따른다.
/// 앱을 다시 켜면 초기화되는 세션 한정 선택이다.
class SportOverrideNotifier extends Notifier<String?> {
  @override
  String? build() {
    // 로그아웃 시 반드시 비운다. 안 그러면 다음 로그인 계정이 이전 계정이 고른
    // 종목으로 등급·추천·룰북·클럽 필터를 보게 된다(RecoveryModeNotifier 와 동일 원칙).
    ref.listen(authStateProvider, (_, next) {
      if (next.value?.event == AuthChangeEvent.signedOut) {
        state = null;
      }
    });
    return null;
  }

  void select(String? sport) => state = sport;
}

final sportOverrideProvider =
    NotifierProvider<SportOverrideNotifier, String?>(SportOverrideNotifier.new);

/// 사용자의 active 종목 — 앱 전체 필터 기준.
/// 화면에서 고른 종목이 있으면 그것을, 없으면 프로필의 주 종목을 사용한다.
/// 대회 탭에서 종목을 바꾸면 룰북·전체 대회·클럽·챗봇이 함께 따라오게 하기 위한
/// 단일 기준점이다(예전에는 대회 탭 안에서만 바뀌어 화면마다 종목이 어긋났다).
final activeSportProvider = Provider<String?>((ref) {
  final override = ref.watch(sportOverrideProvider);
  if (override != null) return override;
  final sports = ref.watch(userSportsProvider).value ?? [];
  return primarySportFrom(sports);
});

typedef HomeTournamentSearch = Future<List<Tournament>> Function({
  required String sport,
  required bool onlyMyGrade,
  required int limit,
});

/// 홈에서 종목별 결과가 서로의 50건 제한을 잠식하지 않도록 각각 조회한다.
Future<List<Tournament>> loadHomeTournamentsBySport({
  required bool hasGradeBasis,
  required DateTime now,
  required HomeTournamentSearch search,
}) async {
  const sports = ['futsal', 'tennis'];
  final matchedBySport = await Future.wait(
    sports.map(
      (sport) => search(
        sport: sport,
        onlyMyGrade: hasGradeBasis,
        limit: 50,
      ),
    ),
  );
  final today = kstTodayDate(now);
  final result = <Tournament>[];

  for (var index = 0; index < sports.length; index += 1) {
    final matched = matchedBySport[index];
    final hasUpcoming = matched.any((item) => !item.startDate.isBefore(today));
    if (hasGradeBasis && !hasUpcoming) {
      try {
        result.addAll(
          await search(
            sport: sports[index],
            onlyMyGrade: false,
            limit: 50,
          ),
        );
        continue;
      } catch (_) {
        // fallback 조회 실패 시 해당 종목의 1차 결과라도 보존한다.
      }
    }
    result.addAll(matched);
  }

  return result;
}

/// 대회 홈은 사용자가 화면에서 종목을 바꿀 수 있으므로 두 종목을 함께 받아오고,
/// 화면에서 선택한 종목만 즉시 보여준다.
final homeTournamentsProvider = FutureProvider<List<Tournament>>((ref) async {
  ref.watch(authStateProvider);
  final api = ref.watch(apiProvider);
  final sports = ref.watch(userSportsProvider).value ?? const [];
  final tennisOrgs = ref.watch(userTennisOrgsProvider).value ?? const [];
  // 등급·협회 등록이 하나도 없으면 자격 매칭이 전부 실패해 목록이 빈다.
  // 그 경우엔 전체 published 를 보여준다(등록이 있으면 내 등급 필터 유지).
  final hasGradeBasis = sports.isNotEmpty || tennisOrgs.isNotEmpty;
  // 임시책(지역↔KATO 등급 대응표 완성 전): 내 등급 매칭 중 '다가오는' 대회가
  // 하나도 없는 종목만 전체 대회로 fallback 해 추천이 비지 않게 한다.
  // 예) 광주 등급 유저에게 8월 KATO 전국대회가 등급 불일치로 전부 걸러지는 경우.
  return loadHomeTournamentsBySport(
    hasGradeBasis: hasGradeBasis,
    now: DateTime.now(),
    search: ({required sport, required onlyMyGrade, required limit}) =>
        api.searchTournaments(
          sport: sport,
          onlyMyGrade: onlyMyGrade,
          limit: limit,
        ),
  );
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
