import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum Sport { tennis, futsal }

const tennisGrades = ['under1y', 'y1to3', 'y3to5', 'over5y'];
const futsalGrades = ['intro', 'beginner', 'intermediate', 'advanced', 'elite'];

const gradeLabels = <String, String>{
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
  final bool hasRanking;
  final String gender; // 'male' | 'female' | 'mixed' | 'all'
  const TennisDivision({
    required this.code,
    required this.org,
    required this.label,
    this.hasRanking = false,
    this.gender = 'all',
  });
}

const _kFallbackDivisions = <TennisDivision>[
  // 광주광역시 (gj) — 남자 랭킹 배점
  TennisDivision(
      code: 'gj_m_open',
      org: 'gj',
      label: '오픈부',
      hasRanking: true,
      gender: 'male'),
  TennisDivision(
      code: 'gj_m_gold',
      org: 'gj',
      label: '골드부',
      hasRanking: true,
      gender: 'male'),
  TennisDivision(
      code: 'gj_m_general',
      org: 'gj',
      label: '일반부',
      hasRanking: true,
      gender: 'male'),
  TennisDivision(
      code: 'gj_m_instructor',
      org: 'gj',
      label: '지도자부',
      hasRanking: true,
      gender: 'male'),
  // 광주 — 선택 부서
  TennisDivision(
      code: 'gj_m_masters', org: 'gj', label: '마스터즈부', gender: 'male'),
  TennisDivision(code: 'gj_m_rookie', org: 'gj', label: '신인부', gender: 'male'),
  TennisDivision(
      code: 'gj_m_veteran', org: 'gj', label: '베테랑부', gender: 'male'),
  TennisDivision(
      code: 'gj_m_beginner', org: 'gj', label: '초급자부', gender: 'male'),
  // 광주 — 여자
  TennisDivision(
      code: 'gj_w_open', org: 'gj', label: '여자오픈부', gender: 'female'),
  TennisDivision(
      code: 'gj_w_winner',
      org: 'gj',
      label: '여자우승자부',
      hasRanking: true,
      gender: 'female'),
  TennisDivision(
      code: 'gj_w_rookie',
      org: 'gj',
      label: '여자신인부',
      hasRanking: true,
      gender: 'female'),
  // 광주 — 혼성
  TennisDivision(code: 'gj_couple', org: 'gj', label: '부부부', gender: 'mixed'),
  TennisDivision(code: 'gj_cross', org: 'gj', label: '크로스대회', gender: 'mixed'),

  // 전라남도 (jn)
  TennisDivision(
      code: 'jn_m_open',
      org: 'jn',
      label: '오픈부',
      hasRanking: true,
      gender: 'male'),
  TennisDivision(
      code: 'jn_m_gold',
      org: 'jn',
      label: '골드부',
      hasRanking: true,
      gender: 'male'),
  TennisDivision(
      code: 'jn_m_general',
      org: 'jn',
      label: '일반부',
      hasRanking: true,
      gender: 'male'),
  TennisDivision(
      code: 'jn_m_instructor',
      org: 'jn',
      label: '지도자부',
      hasRanking: true,
      gender: 'male'),
  TennisDivision(
      code: 'jn_m_masters', org: 'jn', label: '마스터즈부', gender: 'male'),
  TennisDivision(code: 'jn_m_rookie', org: 'jn', label: '신인부', gender: 'male'),
  TennisDivision(
      code: 'jn_m_veteran', org: 'jn', label: '베테랑부', gender: 'male'),
  TennisDivision(
      code: 'jn_m_beginner', org: 'jn', label: '초급자부', gender: 'male'),
  TennisDivision(
      code: 'jn_w_open', org: 'jn', label: '여자오픈부', gender: 'female'),
  TennisDivision(
      code: 'jn_w_winner',
      org: 'jn',
      label: '여자우승자부',
      hasRanking: true,
      gender: 'female'),
  TennisDivision(
      code: 'jn_w_rookie',
      org: 'jn',
      label: '여자신인부',
      hasRanking: true,
      gender: 'female'),
  TennisDivision(code: 'jn_couple', org: 'jn', label: '부부부', gender: 'mixed'),
  TennisDivision(code: 'jn_cross', org: 'jn', label: '크로스대회', gender: 'mixed'),

  // KTA
  TennisDivision(code: 'kta_m_open', org: 'kta', label: '남자오픈', gender: 'male'),
  TennisDivision(
      code: 'kta_w_open', org: 'kta', label: '여자오픈', gender: 'female'),
  TennisDivision(code: 'kta_mixed', org: 'kta', label: '혼합복식', gender: 'mixed'),
  TennisDivision(code: 'kta_senior_60', org: 'kta', label: '시니어 60+'),
  TennisDivision(code: 'kta_senior_65', org: 'kta', label: '시니어 65+'),

  // KATA — 부수제
  TennisDivision(code: 'kata_1', org: 'kata', label: '1부', gender: 'male'),
  TennisDivision(code: 'kata_2', org: 'kata', label: '2부', gender: 'male'),
  TennisDivision(code: 'kata_3', org: 'kata', label: '3부', gender: 'male'),
  TennisDivision(code: 'kata_4', org: 'kata', label: '4부', gender: 'male'),
  TennisDivision(code: 'kata_5', org: 'kata', label: '5부', gender: 'male'),
  TennisDivision(code: 'kata_w', org: 'kata', label: '여자부', gender: 'female'),

  // KTFS
  TennisDivision(code: 'ktfs_open', org: 'ktfs', label: '오픈'),
  TennisDivision(code: 'ktfs_general', org: 'ktfs', label: '일반'),
  TennisDivision(code: 'ktfs_beginner', org: 'ktfs', label: '초급'),
  TennisDivision(code: 'ktfs_w', org: 'ktfs', label: '여자부', gender: 'female'),

  // KSTF (시니어)
  TennisDivision(code: 'kstf_60', org: 'kstf', label: '60+부'),
  TennisDivision(code: 'kstf_65', org: 'kstf', label: '65+부'),
  TennisDivision(code: 'kstf_70', org: 'kstf', label: '70+부'),

  // 지역/클럽 자체
  TennisDivision(code: 'local_open', org: 'local', label: '자체 오픈'),
  TennisDivision(code: 'local_general', org: 'local', label: '자체 일반'),
  TennisDivision(code: 'local_rookie', org: 'local', label: '자체 신인'),
  TennisDivision(
      code: 'local_w', org: 'local', label: '자체 여자부', gender: 'female'),
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
  Future<void> get whenReady => _ready.future;
  void _markReady() {
    if (!_ready.isCompleted) _ready.complete();
  }

  bool get isLoaded => _ordered != null;

  /// 로드됐으면 DB 결과, 아니면 const fallback.
  List<TennisDivision> get all => _ordered ?? _kFallbackDivisions;

  TennisDivision? byCode(String code) =>
      (_byCode ?? _kFallbackByCode)[code];

  /// tennis_divisions 를 읽어 카탈로그를 교체한다(멱등).
  /// 실패(네트워크/RLS/타임아웃) 시 예외를 삼키고 기존 상태를 유지한다.
  Future<void> load(SupabaseClient client) async {
    try {
      final rows = await client
          .from('tennis_divisions')
          .select('code, org_code, label_ko, gender')
          .eq('is_active', true)
          .order('code');
      ingestRows((rows as List).cast<Map<String, dynamic>>());
    } catch (_) {
      // fallback 유지 — 앱 진입 차단 금지.
    } finally {
      _markReady();
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
            ))
        .toList();
    final ordered = _sortByOrgPriority(divisions);
    _ordered = ordered;
    _byCode = {for (final d in ordered) d.code: d};
    _markReady();
  }

  @visibleForTesting
  void reset() {
    _ordered = null;
    _byCode = null;
    _ready = Completer<void>();
  }

  /// tennisOrgs 순서로 org 그룹핑(안정 정렬: 그룹 내 입력 순서 보존).
  /// DB 는 order('code') 로 오지만 협회 그룹핑이 흐트러지므로 재그룹핑한다.
  static List<TennisDivision> _sortByOrgPriority(List<TennisDivision> input) {
    final buckets = <String, List<TennisDivision>>{};
    final unknown = <TennisDivision>[];
    for (final d in input) {
      if (tennisOrgs.contains(d.org)) {
        (buckets[d.org] ??= <TennisDivision>[]).add(d);
      } else {
        unknown.add(d);
      }
    }
    final result = <TennisDivision>[];
    for (final org in tennisOrgs) {
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

/// 특정 org의 division 목록 반환
List<TennisDivision> divisionsForOrg(String org) =>
    tennisDivisions.where((d) => d.org == org).toList();

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
// Tennis Org (협회) — Edge Functions enums.ts 와 1:1 동기화
// =========================
const tennisOrgs = <String>[
  'kta',
  'kato',
  'kata',
  'ktfs',
  'kstf',
  'kssta',
  'kasta',
  'gj',
  'jn',
  'local',
];

const tennisOrgLabels = <String, String>{
  'kta': '대한테니스협회 (KTA)',
  'kato': '한국테니스발전협의회 (KATO)',
  'kata': '한국동호인테니스협회 (KATA)',
  'ktfs': '국민생활체육 전국테니스연합회 (KTFS)',
  'kstf': '한국시니어테니스연맹 (KSTF, 60+)',
  'kssta': '한국슈퍼시니어테니스협회 (KSSTA)',
  'kasta': '단식 테니스 (KASTA / 단테매)',
  'gj': '광주광역시테니스협회 (GJTA)',
  'jn': '전라남도테니스협회 (JNTA)',
  'local': '시·군 또는 클럽 자체',
};

const tennisOrgShortLabels = <String, String>{
  'kta': 'KTA',
  'kato': 'KATO',
  'kata': 'KATA',
  'ktfs': 'KTFS',
  'kstf': 'KSTF',
  'kssta': 'KSSTA',
  'kasta': 'KASTA',
  'gj': '광주협회',
  'jn': '전남협회',
  'local': '시·군/클럽',
};

bool isValidTennisOrg(String value) => tennisOrgs.contains(value);
String tennisOrgLabel(String org) => tennisOrgLabels[org] ?? org;
String tennisOrgShortLabel(String org) => tennisOrgShortLabels[org] ?? org;

// =========================
// Region (권역)
// =========================
const regionCodes = <String>[
  'gwangju',
  'jeonnam',
  'seoul_metro',
  'busan_ulsan_gn',
  'daegu_gb',
  'chungcheong',
  'gangwon',
  'jeju',
];

const regionLabels = <String, String>{
  'gwangju': '광주',
  'jeonnam': '전남',
  'seoul_metro': '수도권',
  'busan_ulsan_gn': '부산·울산·경남',
  'daegu_gb': '대구·경북',
  'chungcheong': '충청',
  'gangwon': '강원',
  'jeju': '제주',
};

bool isValidRegionCode(String value) => regionCodes.contains(value);
String regionLabel(String code) => regionLabels[code] ?? code;
