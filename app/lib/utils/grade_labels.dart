import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum Sport { tennis, futsal }

/// 카탈로그(등급·부서) 교체 알림. 값 자체는 의미 없고 "바뀌었다"는 신호만 쓴다.
///
/// 두 카탈로그는 plain singleton 이라 라벨을 읽는 화면에 리빌드 트리거가 없다.
/// 스플래시 게이트가 콜드스타트는 막지만, 로그아웃 상태로 시작해 로그인하거나
/// 로드가 3초를 넘기면 화면이 폴백 라벨로 그려진 뒤 그대로 굳는다(#318).
/// router.dart 의 `_catalogAware` 가 이걸 듣고 라우트 화면을 새로 만들어 그 경로를 덮는다.
final catalogRevision = ValueNotifier<int>(0);

/// 카탈로그 라벨을 읽는 화면을 감싼다. revision 이 바뀌면 `build` 를 다시 호출해
/// 화면을 **새로 만든다**.
///
/// 화면을 새로 만드는 게 핵심이다 — 같은 인스턴스를 돌려주면 Flutter 가
/// `identical()` 패스트패스로 하위 트리 갱신을 통째로 건너뛴다. 그래서
/// `catalogAware(() => const XScreen())` 처럼 클로저 안에 `const` 를 두면
/// **감싸도 갱신되지 않는다**(const 표현식은 canonicalize 되어 매번 같은 객체다).
/// 위젯 타입·위치가 같으므로 State(스크롤 위치·입력값)는 보존된다.
///
/// 라우트는 router.dart 가 일괄로 감싼다. 라우트가 아닌 표면(showModalBottomSheet·
/// showDialog 로 뜨는 시트·다이얼로그)은 그 위젯 트리의 자손이 아니므로 각자 감싸야 한다.
Widget catalogAware(Widget Function() build) => ListenableBuilder(
      listenable: catalogRevision,
      builder: (_, __) => build(),
    );

// 등급 정본은 DB public.grades 다(JY-146 P3-a). 아래 const 는 미로드 시 쓰이는
// 오프라인 폴백이며, harness 게이트(check_enums.py)가 seed 와의 일치를 강제한다.
// 부서 카탈로그(DivisionCatalog)와 같은 구조다.
const _kFallbackTennisGrades = ['under1y', 'y1to3', 'y3to5', 'over5y'];
const _kFallbackFutsalGrades = [
  'intro',
  'beginner',
  'intermediate',
  'advanced',
  'elite'
];

const _kFallbackGradeLabels = <String, String>{
  'under1y': '1년 미만',
  'y1to3': '1~3년',
  'y3to5': '3~5년',
  'over5y': '5년 이상',
  'intro': '입문',
  'beginner': '초급',
  'intermediate': '중급',
  'advanced': '고급',
  'elite': '선출',
};

/// 등급 카탈로그: 미로드 시 const 폴백, load 성공 시 DB 결과로 교체.
/// 등급 추가·개명이 grades INSERT/UPDATE 만으로 앱에 반영된다.
class GradeCatalog {
  GradeCatalog._();
  static final GradeCatalog instance = GradeCatalog._();

  // 선택지는 활성 등급만, 라벨은 폐기 등급까지. 폐기해도 그 등급을 쓰던 사용자의
  // 프로필에는 코드가 아니라 이름이 보여야 한다.
  Map<Sport, List<String>>? _activeCodes;
  Map<String, String>? _labels;

  // 로드 세대. 세션 전환(reset)이 in-flight 로드를 무효화해, 늦게 도착한 이전 계정의
  // 결과가 새 상태를 오염시키지 않게 한다(DivisionCatalog 와 같은 이유).
  int _generation = 0;
  Completer<void> _ready = Completer<void>();

  /// 로드 시도(성공·실패 무관) 완료 신호. 스플래시 게이트가 이걸 기다려 첫 화면이
  /// 폴백 라벨로 그려졌다가 바뀌는 걸 막는다.
  Future<void> get whenReady => _ready.future;
  void _markReady() {
    if (!_ready.isCompleted) _ready.complete();
  }

  bool get isLoaded => _activeCodes != null;

  List<String> codesFor(Sport sport) {
    final loaded = _activeCodes;
    // 로드됐으면 그 결과가 정본이다. 한 종목의 활성 등급이 0개면 빈 목록이 맞고,
    // 폴백을 되살리면 DB 의 폐기 결정을 앱이 뒤집는 꼴이 된다.
    if (loaded != null) return loaded[sport] ?? const [];
    return sport == Sport.tennis
        ? _kFallbackTennisGrades
        : _kFallbackFutsalGrades;
  }

  Map<String, String> get labels => _labels ?? _kFallbackGradeLabels;

  /// grades 를 읽어 카탈로그를 교체한다(멱등).
  /// 실패(네트워크/RLS/타임아웃) 시 예외를 삼키고 폴백을 유지한다 — 등급 선택지가
  /// 비어 앱이 막히는 것보다 낫다.
  Future<void> load(SupabaseClient client) async {
    final gen = ++_generation;
    try {
      // 폐기 등급까지 받아 라벨을 채운다. 선택지 필터는 is_active 로 아래에서 한다.
      final rows = await client
          .from('grades')
          .select('sport, code, label_ko, is_active')
          .order('sport')
          .order('sort_order');
      if (gen == _generation) {
        ingestRows((rows as List).cast<Map<String, dynamic>>());
      }
    } catch (_) {
      // 폴백 유지.
    } finally {
      if (gen == _generation) _markReady();
    }
  }

  /// DB row(또는 테스트 픽스처) → 카탈로그. 정렬은 쿼리(sort_order)가 보장한다.
  @visibleForTesting
  void ingestRows(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      // 빈 응답으로 선택지를 통째로 지우지 않는다(권한·필터 사고 방어).
      _markReady();
      return;
    }
    final codes = <Sport, List<String>>{};
    final labels = <String, String>{};
    for (final row in rows) {
      final sport = sportFromString(row['sport'] as String);
      final code = row['code'] as String;
      labels[code] = row['label_ko'] as String;
      if (row['is_active'] as bool? ?? true) {
        (codes[sport] ??= <String>[]).add(code);
      }
    }
    _activeCodes = codes;
    _labels = labels;
    _markReady();
    catalogRevision.value++;
  }

  /// 세션 전환(로그아웃·계정 변경) 시 호출한다. in-flight 로드도 무효화된다.
  void reset() {
    _activeCodes = null;
    _labels = null;
    _ready = Completer<void>();
    _generation++;
    catalogRevision.value++;
  }
}

/// 종목별 등급 코드(표시 순서). 로드됐으면 DB, 아니면 const 폴백.
List<String> get tennisGrades => GradeCatalog.instance.codesFor(Sport.tennis);
List<String> get futsalGrades => GradeCatalog.instance.codesFor(Sport.futsal);

/// 등급 코드 → 라벨 맵.
Map<String, String> get gradeLabels => GradeCatalog.instance.labels;

/// 등급 무관. 등급 코드가 아니라 "가리지 않음"을 뜻하는 선택지 라벨이다.
const anyGradeLabel = '무관';

/// 팀 모집글 `skill_level` 에 저장 가능한 라벨(해당 종목의 등급 라벨 ∪ 무관).
/// 종목을 받는 이유: 합집합으로 검사하면 풋살 모집글에 '1년 미만'(테니스 등급)이
/// 들어가도 통과한다. free-text 컬럼이라 DB 가 막지 못하는 오염을 코드 경계에서 거른다.
bool isAllowedSkillLevelLabel(Sport sport, String value) =>
    value == anyGradeLabel || gradesFor(sport).map(gradeLabel).contains(value);

const futsalEventCategoryLabels = <String, String>{
  'regional_federation': '지역 풋살연맹',
  'sports_for_all': '생활체육대회',
  'private': '민간 풋살 대회',
};

// =========================
// 협회별 부서 코드 ({org}_{div}) — tournaments.eligible_grades 용
// =========================

/// 협회별 부서 정의
class TennisDivision {
  final String code;
  final String org;
  final String label;

  /// 개인이 자기 랭킹 등급으로 속할 수 있는가(DB tennis_divisions.is_ranking_grade).
  /// false = 대회 출전 종목 전용 — 대회 라벨로는 쓰이지만 온보딩 칩에는 뜨지 않는다.
  /// 예: 초급자부(경력 기준 별도 대회), 마스터즈부, 혼합복식, 지동부.
  /// 기본 true — 대부분의 부서가 등급이고 예외만 명시한다(DB default 와 동일).
  final bool isRankingGrade;
  final String gender; // 'male' | 'female' | 'mixed' | 'all'
  const TennisDivision({
    required this.code,
    required this.org,
    required this.label,
    this.isRankingGrade = true,
    this.gender = 'all',
  });
}

const _kFallbackDivisions = <TennisDivision>[
  // 광주광역시 (gj) — 남자
  TennisDivision(
      code: 'gj_m_open',
      org: 'gj',
      label: '오픈부',
      gender: 'male'),
  TennisDivision(
      code: 'gj_m_gold',
      org: 'gj',
      label: '골드부',
      gender: 'male'),
  TennisDivision(
      code: 'gj_m_general',
      org: 'gj',
      label: '일반부',
      gender: 'male'),
  TennisDivision(
      code: 'gj_m_instructor',
      org: 'gj',
      label: '지도자부',
      gender: 'male'),
  // 광주 — 대회 종목 전용(개인 등급 아님)이 섞여 있다
  TennisDivision(
      code: 'gj_m_masters',
      org: 'gj',
      label: '마스터즈부',
      isRankingGrade: false,
      gender: 'male'),
  TennisDivision(code: 'gj_m_rookie', org: 'gj', label: '신인부', gender: 'male'),
  TennisDivision(
      code: 'gj_m_veteran', org: 'gj', label: '베테랑부', gender: 'male'),
  TennisDivision(
      code: 'gj_m_beginner',
      org: 'gj',
      label: '초급자부',
      isRankingGrade: false,
      gender: 'male'),
  TennisDivision(
      code: 'gj_m_jidong',
      org: 'gj',
      label: '지동부',
      isRankingGrade: false,
      gender: 'male'),
  // 광주 — 여자
  TennisDivision(
      code: 'gj_w_open', org: 'gj', label: '여자오픈부', gender: 'female'),
  TennisDivision(
      code: 'gj_w_winner',
      org: 'gj',
      label: '여자우승자부',
      gender: 'female'),
  TennisDivision(
      code: 'gj_w_rookie',
      org: 'gj',
      label: '여자신인부',
      gender: 'female'),
  // 광주 — 혼성

  // 전라남도 (jn)
  TennisDivision(
      code: 'jn_m_open',
      org: 'jn',
      label: '오픈부',
      gender: 'male'),
  TennisDivision(
      code: 'jn_m_gold',
      org: 'jn',
      label: '골드부',
      gender: 'male'),
  TennisDivision(
      code: 'jn_m_general',
      org: 'jn',
      label: '일반부',
      gender: 'male'),
  TennisDivision(
      code: 'jn_m_instructor',
      org: 'jn',
      label: '지도자부',
      gender: 'male'),
  TennisDivision(
      code: 'jn_m_masters',
      org: 'jn',
      label: '마스터즈부',
      isRankingGrade: false,
      gender: 'male'),
  TennisDivision(code: 'jn_m_rookie', org: 'jn', label: '신인부', gender: 'male'),
  TennisDivision(
      code: 'jn_m_veteran', org: 'jn', label: '베테랑부', gender: 'male'),
  TennisDivision(
      code: 'jn_m_beginner',
      org: 'jn',
      label: '초급자부',
      isRankingGrade: false,
      gender: 'male'),
  TennisDivision(
      code: 'jn_w_open', org: 'jn', label: '여자오픈부', gender: 'female'),
  TennisDivision(
      code: 'jn_w_winner',
      org: 'jn',
      label: '여자우승자부',
      gender: 'female'),
  TennisDivision(
      code: 'jn_w_rookie',
      org: 'jn',
      label: '여자신인부',
      gender: 'female'),

  // KTA
  TennisDivision(code: 'kta_m_open', org: 'kta', label: '남자오픈', gender: 'male'),
  TennisDivision(
      code: 'kta_w_open', org: 'kta', label: '여자오픈', gender: 'female'),
  TennisDivision(
      code: 'kta_mixed',
      org: 'kta',
      label: '혼합복식',
      isRankingGrade: false,
      gender: 'mixed'),
  TennisDivision(code: 'kta_senior_60', org: 'kta', label: '시니어 60+'),
  TennisDivision(code: 'kta_senior_65', org: 'kta', label: '시니어 65+'),

  // KATA — 부수제
  TennisDivision(code: 'kata_1', org: 'kata', label: '1부', gender: 'male'),
  TennisDivision(code: 'kata_2', org: 'kata', label: '2부', gender: 'male'),
  TennisDivision(code: 'kata_3', org: 'kata', label: '3부', gender: 'male'),
  TennisDivision(code: 'kata_4', org: 'kata', label: '4부', gender: 'male'),
  TennisDivision(code: 'kata_5', org: 'kata', label: '5부', gender: 'male'),
  TennisDivision(code: 'kata_w', org: 'kata', label: '여자부', gender: 'female'),

  // KSTF (시니어)
  TennisDivision(code: 'kstf_60', org: 'kstf', label: '60+부'),
  TennisDivision(code: 'kstf_65', org: 'kstf', label: '65+부'),
  TennisDivision(code: 'kstf_70', org: 'kstf', label: '70+부'),

  // KTFS(2016년 KTA 흡수·소멸)·local(클럽 자체 임시 등급)은 DB 에서 is_active=false 라
  // 폴백에서도 뺀다 — 남겨두면 DB 로드 실패 시에만 유령처럼 되살아난다.
];

/// 부서 카탈로그: 미로드 시 const fallback, load 성공 시 DB 결과로 완전 교체.
/// 신규 협회 부서 추가가 DB INSERT 만으로 앱에 반영되게 하는 단일 진실 소스.
class DivisionCatalog {
  DivisionCatalog._();
  static final DivisionCatalog instance = DivisionCatalog._();

  // null = 미로드 → const fallback 사용.
  List<TennisDivision>? _ordered;
  Map<String, TennisDivision>? _byCode;

  // JY-121: 로드 시도(성공/실패 무관) 완료 신호. 스플래시 게이트가 이걸 기다려
  // 첫 화면 빌드 전 카탈로그를 준비, stale fallback(kato 원문 노출)을 예방한다.
  Completer<void> _ready = Completer<void>();
  // load 세대 카운터. reset()/재로드가 in-flight load 를 무효화해, 늦게 도착한
  // 옛 load 결과가 새 상태·새 _ready 를 오염시키지 않게 한다(Codex P2).
  int _generation = 0;
  Future<void> get whenReady => _ready.future;
  void _markReady() {
    if (!_ready.isCompleted) _ready.complete();
  }

  bool get isLoaded => _ordered != null;

  /// 로드됐으면 DB 결과, 아니면 const fallback.
  List<TennisDivision> get all => _ordered ?? _kFallbackDivisions;

  TennisDivision? byCode(String code) => (_byCode ?? _kFallbackByCode)[code];

  /// tennis_divisions 를 읽어 카탈로그를 교체한다(멱등).
  /// 실패(네트워크/RLS/타임아웃) 시 예외를 삼키고 기존 상태를 유지한다.
  Future<void> load(SupabaseClient client) async {
    final gen = ++_generation;
    try {
      final rows = await client
          .from('tennis_divisions')
          .select('code, org_code, label_ko, gender, is_ranking_grade')
          .eq('is_active', true)
          .order('code');
      // reset()/재로드로 세대가 바뀌었으면 이 결과는 버린다(stale 반영 방지).
      if (gen == _generation) {
        ingestRows((rows as List).cast<Map<String, dynamic>>());
      }
    } catch (_) {
      // fallback 유지 — 앱 진입 차단 금지.
    } finally {
      if (gen == _generation) _markReady();
    }
  }

  /// DB row(또는 테스트 픽스처) → 카탈로그. org 우선순위로 그룹핑해 교체.
  @visibleForTesting
  void ingestRows(List<Map<String, dynamic>> rows) {
    final divisions = rows
        .map((r) => TennisDivision(
              code: r['code'] as String,
              org: r['org_code'] as String,
              label: r['label_ko'] as String,
              gender: (r['gender'] as String?) ?? 'all',
              // 컬럼이 없는 구버전 응답이면 true — 기존 동작(전부 등급)을 유지한다.
              isRankingGrade: (r['is_ranking_grade'] as bool?) ?? true,
            ))
        .toList();
    final ordered = _sortByOrgPriority(divisions);
    _ordered = ordered;
    _byCode = {for (final d in ordered) d.code: d};
    _markReady();
    catalogRevision.value++;
  }

  /// 세션 전환(로그아웃·계정 변경) 시 호출한다. GradeCatalog.reset 과 같은 이유로,
  /// 재로그인 로드가 실패했을 때 이전 계정의 부서 스냅샷이 남는 걸 막는다(#318).
  void reset() {
    _ordered = null;
    _byCode = null;
    _ready = Completer<void>();
    _generation++;
    catalogRevision.value++;
  }

  /// OrgCatalog 순서로 org 그룹핑(안정 정렬: 그룹 내 입력 순서 보존).
  /// DB 는 order('code') 로 오지만 협회 그룹핑이 흐트러지므로 재그룹핑한다.
  /// 비활성 협회의 부서도 순서를 가져야 하므로 activeCodes(tennisOrgs) 가 아니라
  /// all 을 쓴다 — activeCodes 만 쓰면 비활성 협회 부서가 순서 없이 뒤로 밀린다.
  static List<TennisDivision> _sortByOrgPriority(List<TennisDivision> input) {
    final orgOrder = OrgCatalog.instance.all.map((o) => o.code).toList();
    final buckets = <String, List<TennisDivision>>{};
    final unknown = <TennisDivision>[];
    for (final d in input) {
      if (orgOrder.contains(d.org)) {
        (buckets[d.org] ??= <TennisDivision>[]).add(d);
      } else {
        unknown.add(d);
      }
    }
    final result = <TennisDivision>[];
    for (final org in orgOrder) {
      final bucket = buckets[org];
      if (bucket != null) result.addAll(bucket);
    }
    result.addAll(unknown);
    return result;
  }
}

final _kFallbackByCode = <String, TennisDivision>{
  for (final d in _kFallbackDivisions) d.code: d,
};

/// 부서 목록: 카탈로그 위임(로드됐으면 DB, 아니면 const fallback).
List<TennisDivision> get tennisDivisions => DivisionCatalog.instance.all;

/// division 코드 → 표시명 (미등록 코드는 코드 그대로 반환)
String divisionLabel(String code) =>
    DivisionCatalog.instance.byCode(code)?.label ?? gradeLabels[code] ?? code;

/// 특정 org의 division 목록 반환 — **대회가 열 수 있는 종목 전체**.
/// 대회 제보 화면이 쓴다(초급자부·마스터즈부 대회도 제보돼야 한다).
List<TennisDivision> divisionsForOrg(String org) =>
    tennisDivisions.where((d) => d.org == org).toList();

/// 특정 org 에서 **유저가 자기 등급으로 고를 수 있는** 부서만 반환한다 — 온보딩용.
/// 대회 종목 전용(초급자부·마스터즈부·혼합복식·지동부)은 빠진다.
/// 대회 쪽 목록·라벨 해석에는 divisionsForOrg/divisionLabel 을 그대로 써야 한다.
List<TennisDivision> rankingGradesForOrg(String org) =>
    divisionsForOrg(org).where((d) => d.isRankingGrade).toList();

/// 부서 라벨 그룹: 라벨이 같은 부서 코드를 협회 무관하게 묶는다.
/// 예) '골드부' → ['gj_m_gold', 'jn_m_gold']
///
/// 첫 등장 순서를 보존한 유니크 라벨 리스트를 반환한다(상세검색 칩 순서용).
List<String> tennisDivisionLabels() {
  final seen = <String>{};
  final ordered = <String>[];
  for (final d in tennisDivisions) {
    if (seen.add(d.label)) ordered.add(d.label);
  }
  return ordered;
}

/// 라벨 → 해당 라벨을 가진 모든 부서 코드(협회 무관).
/// 미등록 라벨은 빈 리스트.
List<String> tennisCodesForLabel(String label) =>
    tennisDivisions.where((d) => d.label == label).map((d) => d.code).toList();

/// 선택된 부서 라벨 집합 → 합쳐진 부서 코드 집합.
/// 한 라벨이 여러 협회 코드를 가지면 모두 합친다.
Set<String> tennisCodesForLabels(Iterable<String> labels) {
  final codes = <String>{};
  for (final label in labels) {
    codes.addAll(tennisCodesForLabel(label));
  }
  return codes;
}

/// 특정 협회(org)의 부서 라벨: 첫 등장 순서를 보존한 유니크 라벨.
/// org 가 미등록이면 빈 리스트.
List<String> tennisDivisionLabelsForOrg(String org) {
  final seen = <String>{};
  final ordered = <String>[];
  for (final d in divisionsForOrg(org)) {
    if (seen.add(d.label)) ordered.add(d.label);
  }
  return ordered;
}

/// 특정 협회(org) 안에서 라벨 → 그 org 의 부서 코드.
/// 같은 org 내에 동일 라벨이 여럿이면 모두 포함(보통 1개).
List<String> tennisCodesForLabelInOrg(String org, String label) =>
    divisionsForOrg(org)
        .where((d) => d.label == label)
        .map((d) => d.code)
        .toList();

/// 특정 협회(org) 안에서 라벨 집합 → 그 org 의 부서 코드 집합.
Set<String> tennisCodesForLabelsInOrg(String org, Iterable<String> labels) {
  final codes = <String>{};
  for (final label in labels) {
    codes.addAll(tennisCodesForLabelInOrg(org, label));
  }
  return codes;
}

/// eligible_grades 코드 배열 → "골드부 · 일반부 · 신인부" 표시 문자열
String formatEligibleGrades(List<String> codes) {
  if (codes.isEmpty) return '-';
  return codes.map(divisionLabel).join(' · ');
}

const sportLabels = <Sport, String>{
  Sport.tennis: '테니스',
  Sport.futsal: '풋살',
};

Sport sportFromString(String s) => s == 'futsal' ? Sport.futsal : Sport.tennis;

String sportToString(Sport s) => s == Sport.futsal ? 'futsal' : 'tennis';

List<String> gradesFor(Sport sport) =>
    sport == Sport.tennis ? tennisGrades : futsalGrades;

String gradeLabel(String grade) => gradeLabels[grade] ?? grade;
String sportLabel(Sport sport) => sportLabels[sport] ?? '';
String sportLabelFromString(String s) => sportLabel(sportFromString(s));
String futsalEventCategoryLabel(String? category) =>
    category == null ? '' : futsalEventCategoryLabels[category] ?? category;

// =========================
// Tennis Org (협회) — 정본은 DB public.tennis_orgs (JY-135)
// =========================

/// 협회 카탈로그 항목. 정본은 DB public.tennis_orgs 다(JY-135).
class TennisOrgEntry {
  const TennisOrgEntry({
    required this.code,
    required this.label,
    required this.shortLabel,
    required this.isActive,
  });

  final String code;
  final String label;
  final String shortLabel;
  final bool isActive;
}

// 협회 정본은 DB public.tennis_orgs 다(JY-135). 아래 const 는 미로드 시 쓰는
// 오프라인 폴백이며, 값은 마이그레이션 백필과 같아야 한다.
const _kFallbackOrgEntries = <TennisOrgEntry>[
  TennisOrgEntry(code: 'kta', label: '대한테니스협회 (KTA)', shortLabel: 'KTA', isActive: true),
  TennisOrgEntry(code: 'kato', label: '한국테니스발전협의회 (KATO)', shortLabel: 'KATO', isActive: true),
  TennisOrgEntry(code: 'kata', label: '한국동호인테니스협회 (KATA)', shortLabel: 'KATA', isActive: true),
  TennisOrgEntry(code: 'ktfs', label: '국민생활체육 전국테니스연합회 (KTFS)', shortLabel: 'KTFS', isActive: false),
  TennisOrgEntry(code: 'kstf', label: '한국시니어테니스연맹 (KSTF, 60+)', shortLabel: 'KSTF', isActive: true),
  TennisOrgEntry(code: 'kssta', label: '한국슈퍼시니어테니스협회 (KSSTA)', shortLabel: 'KSSTA', isActive: true),
  TennisOrgEntry(code: 'kasta', label: '단식 테니스 (KASTA / 단테매)', shortLabel: 'KASTA', isActive: true),
  TennisOrgEntry(code: 'gj', label: '광주광역시테니스협회 (GJTA)', shortLabel: '광주협회', isActive: true),
  TennisOrgEntry(code: 'jn', label: '전라남도테니스협회 (JNTA)', shortLabel: '전남협회', isActive: true),
  TennisOrgEntry(code: 'local', label: '시·군 또는 클럽 자체', shortLabel: '시·군/클럽', isActive: true),
];

final _kFallbackOrgByCode = {for (final e in _kFallbackOrgEntries) e.code: e};

/// 협회 목록·라벨 카탈로그. DivisionCatalog 와 같은 구조다(JY-120 선례).
///
/// 협회 추가는 tennis_orgs 에 행을 넣는 것만으로 끝난다 — 앱 재배포가 필요 없다.
class OrgCatalog {
  OrgCatalog._();
  static final OrgCatalog instance = OrgCatalog._();

  // null = 미로드 → const 폴백 사용.
  List<TennisOrgEntry>? _ordered;
  Map<String, TennisOrgEntry>? _byCode;

  Completer<void> _ready = Completer<void>();
  int _generation = 0;
  Future<void> get whenReady => _ready.future;
  void _markReady() {
    if (!_ready.isCompleted) _ready.complete();
  }

  bool get isLoaded => _ordered != null;

  List<TennisOrgEntry> get all => _ordered ?? _kFallbackOrgEntries;

  /// 선택지에 노출할 활성 협회 코드(표시 순서).
  List<String> get activeCodes =>
      all.where((o) => o.isActive).map((o) => o.code).toList(growable: false);

  /// 라벨 조회는 활성 여부와 무관하다 — 비활성 협회를 이미 가진 사용자의
  /// 화면에 코드가 그대로 노출되면 안 된다.
  String labelFor(String code) =>
      (_byCode ?? _kFallbackOrgByCode)[code]?.label ?? code;

  String shortLabelFor(String code) =>
      (_byCode ?? _kFallbackOrgByCode)[code]?.shortLabel ?? code;

  /// tennis_orgs 를 읽어 카탈로그를 교체한다(멱등).
  /// 실패(네트워크/RLS/타임아웃) 시 예외를 삼키고 폴백을 유지한다.
  Future<void> load(SupabaseClient client) async {
    final gen = ++_generation;
    try {
      final rows = await client
          .from('tennis_orgs')
          .select('code, label_ko, short_label, name_ko, is_active, sort_order')
          .order('sort_order')
          .order('name_ko')
          .order('code');
      if (gen == _generation) {
        ingestRows((rows as List).cast<Map<String, dynamic>>());
      }
    } catch (_) {
      // 폴백 유지 — 앱 진입을 막지 않는다.
    } finally {
      if (gen == _generation) _markReady();
    }
  }

  /// DB row(또는 테스트 픽스처) → 카탈로그.
  /// label_ko 가 비면 name_ko 로, short_label 이 비면 label 로 폴백한다.
  /// (sort_order, name_ko, code) 순으로 정렬한다 — load() 의 쿼리 order 와 동일한
  /// 규칙을 여기서도 적용해, 테스트 픽스처처럼 정렬 안 된 입력이 와도 결과가 같다.
  @visibleForTesting
  void ingestRows(List<Map<String, dynamic>> rows) {
    final sorted = [...rows]..sort((a, b) {
        final sortOrderCmp = ((a['sort_order'] as num?) ?? 1000)
            .compareTo((b['sort_order'] as num?) ?? 1000);
        if (sortOrderCmp != 0) return sortOrderCmp;
        final nameCmp = ((a['name_ko'] as String?) ?? '')
            .compareTo((b['name_ko'] as String?) ?? '');
        if (nameCmp != 0) return nameCmp;
        return (a['code'] as String).compareTo(b['code'] as String);
      });
    final entries = sorted.map((r) {
      final code = r['code'] as String;
      final label = (r['label_ko'] as String?) ?? (r['name_ko'] as String?) ?? code;
      return TennisOrgEntry(
        code: code,
        label: label,
        shortLabel: (r['short_label'] as String?) ?? label,
        isActive: (r['is_active'] as bool?) ?? true,
      );
    }).toList();
    _ordered = entries;
    _byCode = {for (final e in entries) e.code: e};
    _markReady();
    catalogRevision.value++;
  }

  /// 세션 전환(로그아웃·계정 변경) 시 호출한다.
  void reset() {
    _ordered = null;
    _byCode = null;
    _ready = Completer<void>();
    _generation++;
    catalogRevision.value++;
  }
}

/// 협회 코드(표시 순서, 활성만). 로드됐으면 DB, 아니면 const 폴백.
List<String> get tennisOrgs => OrgCatalog.instance.activeCodes;

/// 부서가 1개 이상 있는 활성 협회만(제보 화면용, JY-135 P1-2).
/// eligible_grades 는 부서 코드가 필수라, 부서가 0개인 협회를 고르면 제보를
/// 끝낼 수 없다. 부서 카탈로그에서 파생하므로 부서가 추가되면 자동 반영된다.
List<String> get tennisOrgsWithDivisions =>
    tennisOrgs.where((code) => divisionsForOrg(code).isNotEmpty).toList();

/// 협회 코드 → 완성형 라벨.
String tennisOrgLabel(String org) => OrgCatalog.instance.labelFor(org);

/// 협회 코드 → 짧은 라벨(칩·요약용).
String tennisOrgShortLabel(String org) => OrgCatalog.instance.shortLabelFor(org);

// =========================
// Region (표준 17개 광역시도)
// =========================
// 정본: DB public.regions (is_active=true) 와 코드·라벨 1:1. 지도상 순서(수도권→강원→충청→호남→영남→제주).
// 묶음 코드(seoul_metro 등)는 deprecated(regions.is_active=false)라 UI 선택지엔 없지만,
// backfill 이전 데이터의 라벨 표시를 위해 regionLabels 에는 하위호환으로 유지한다.
const regionCodes = <String>[
  'seoul',
  'gyeonggi',
  'incheon',
  'gangwon',
  'daejeon',
  'sejong',
  'chungbuk',
  'chungnam',
  'gwangju',
  'jeonbuk',
  'jeonnam',
  'busan',
  'ulsan',
  'daegu',
  'gyeongbuk',
  'gyeongnam',
  'jeju',
];

const regionLabels = <String, String>{
  // 17개 광역시도 (regions.is_active=true)
  'seoul': '서울',
  'gyeonggi': '경기',
  'incheon': '인천',
  'gangwon': '강원',
  'daejeon': '대전',
  'sejong': '세종',
  'chungbuk': '충북',
  'chungnam': '충남',
  'gwangju': '광주',
  'jeonbuk': '전북',
  'jeonnam': '전남',
  'busan': '부산',
  'ulsan': '울산',
  'daegu': '대구',
  'gyeongbuk': '경북',
  'gyeongnam': '경남',
  'jeju': '제주',
  // deprecated 묶음 코드 — 표시 하위호환용(backfill 이전 데이터)
  'seoul_metro': '수도권',
  'busan_ulsan_gn': '부산·울산·경남',
  'daegu_gb': '대구·경북',
  'chungcheong': '충청',
};

bool isValidRegionCode(String value) => regionCodes.contains(value);
String regionLabel(String code) => regionLabels[code] ?? code;
