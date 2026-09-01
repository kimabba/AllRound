import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:allround/utils/grade_labels.dart';

void main() {
  tearDown(GradeCatalog.instance.reset);

  group('GradeCatalog DB 로드', () {
    test('로드 전에는 폴백 등급을 쓴다', () {
      expect(GradeCatalog.instance.isLoaded, isFalse);
      expect(futsalGrades, ['intro', 'beginner', 'intermediate', 'advanced', 'elite']);
      expect(gradeLabel('elite'), '선출');
    });

    test('DB 결과가 폴백을 대체한다 — 등급 추가·개명이 INSERT 만으로 반영된다', () {
      GradeCatalog.instance.ingestRows([
        {'sport': 'futsal', 'code': 'intro', 'label_ko': '입문', 'is_active': true},
        {'sport': 'futsal', 'code': 'pro', 'label_ko': '프로', 'is_active': true},
        {
          'sport': 'tennis',
          'code': 'under1y',
          'label_ko': '1년 미만',
          'is_active': true
        },
      ]);
      expect(futsalGrades, ['intro', 'pro']);
      expect(gradeLabel('pro'), '프로');
      expect(gradesFor(Sport.tennis), ['under1y']);
      // 새 등급이 곧바로 모집글 허용집합에 들어간다.
      expect(isAllowedSkillLevelLabel(Sport.futsal, '프로'), isTrue);
    });

    test('폐기 등급은 선택지에서 빠지되 라벨은 남는다', () {
      GradeCatalog.instance.ingestRows([
        {'sport': 'futsal', 'code': 'intro', 'label_ko': '입문', 'is_active': true},
        {'sport': 'futsal', 'code': 'pro', 'label_ko': '프로', 'is_active': false},
      ]);
      expect(futsalGrades, ['intro'], reason: '폐기 등급이 선택지에 남았다');
      // 그 등급을 쓰던 사용자의 프로필에 코드가 그대로 노출되면 안 된다.
      expect(gradeLabel('pro'), '프로');
      expect(isAllowedSkillLevelLabel(Sport.futsal, '프로'), isFalse);
    });

    test('한 종목의 활성 등급이 0개면 폴백을 되살리지 않는다', () {
      // 폴백으로 되돌리면 앱이 DB 의 폐기 결정을 뒤집는 꼴이 된다.
      GradeCatalog.instance.ingestRows([
        {'sport': 'tennis', 'code': 'under1y', 'label_ko': '1년 미만', 'is_active': true},
      ]);
      expect(futsalGrades, isEmpty);
      expect(tennisGrades, ['under1y']);
    });

    test('빈 응답은 무시한다 — 선택지가 통째로 사라지면 안 된다', () {
      GradeCatalog.instance.ingestRows([]);
      expect(GradeCatalog.instance.isLoaded, isFalse);
      expect(futsalGrades.length, 5);
    });

    test('ingest 는 whenReady 를 완료시키고 reset 은 재무장한다', () async {
      var ready = false;
      unawaited(GradeCatalog.instance.whenReady.then((_) => ready = true));
      await pumpEventQueue();
      expect(ready, isFalse, reason: '로드 전에 스플래시가 열리면 폴백 라벨이 보인다');

      GradeCatalog.instance.ingestRows([
        {'sport': 'futsal', 'code': 'intro', 'label_ko': '입문', 'is_active': true},
      ]);
      await pumpEventQueue();
      expect(ready, isTrue);

      GradeCatalog.instance.reset();
      var readyAgain = false;
      unawaited(GradeCatalog.instance.whenReady.then((_) => readyAgain = true));
      await pumpEventQueue();
      expect(readyAgain, isFalse, reason: '세션 전환 후에도 이전 완료 신호가 남았다');
    });
  });

  group('skill_level 허용집합', () {
    test('해당 종목의 등급 라벨과 무관은 통과한다', () {
      for (final sport in Sport.values) {
        for (final grade in gradesFor(sport)) {
          expect(isAllowedSkillLevelLabel(sport, gradeLabel(grade)), isTrue,
              reason: '$sport 의 $grade 라벨이 거부됐다');
        }
        expect(isAllowedSkillLevelLabel(sport, anyGradeLabel), isTrue);
      }
    });

    test('다른 종목의 등급 라벨은 거부한다', () {
      // 합집합으로 검사하면 풋살 모집글에 테니스 등급이 들어가도 통과한다.
      expect(isAllowedSkillLevelLabel(Sport.futsal, '1년 미만'), isFalse);
      expect(isAllowedSkillLevelLabel(Sport.tennis, '입문'), isFalse);
    });

    test('폐기된 부수체계와 등급 코드 자체는 거부한다', () {
      // 마이그 010 에서 폐기된 옛 라벨이 다시 유입되는 걸 막는다(JY-146).
      for (final stale in ['신입', '5부', '1부']) {
        expect(isAllowedSkillLevelLabel(Sport.tennis, stale), isFalse,
            reason: '$stale 이 통과됐다');
      }
      // 라벨 자리에 코드가 들어오는 실수도 거른다.
      expect(isAllowedSkillLevelLabel(Sport.tennis, 'under1y'), isFalse);
      expect(isAllowedSkillLevelLabel(Sport.futsal, ''), isFalse);
    });
  });

  group('grade_labels', () {
    test('tennis grade order: under1y → over5y', () {
      expect(tennisGrades, ['under1y', 'y1to3', 'y3to5', 'over5y']);
    });

    test('futsal grade order', () {
      expect(futsalGrades, [
        'intro',
        'beginner',
        'intermediate',
        'advanced',
        'elite',
      ]);
    });

    test('Korean labels', () {
      expect(gradeLabel('y3to5'), '3~5년');
      expect(gradeLabel('under1y'), '1년 미만');
      expect(gradeLabel('intro'), '입문');
      expect(gradeLabel('intermediate'), '중급');
      expect(gradeLabel('elite'), '선출');
      expect(sportLabel(Sport.tennis), '테니스');
      expect(sportLabel(Sport.futsal), '풋살');
    });

    test('sportFromString roundtrip', () {
      expect(sportFromString('tennis'), Sport.tennis);
      expect(sportFromString('futsal'), Sport.futsal);
      expect(sportToString(Sport.tennis), 'tennis');
      expect(sportToString(Sport.futsal), 'futsal');
    });

    test('gradesFor returns sport-specific grades', () {
      expect(gradesFor(Sport.tennis), tennisGrades);
      expect(gradesFor(Sport.futsal), futsalGrades);
    });
  });

  group('tennis division label grouping', () {
    test('tennisDivisionLabels returns unique labels in first-seen order', () {
      final labels = tennisDivisionLabels();
      // 유니크해야 함
      expect(labels.toSet().length, labels.length);
      // 첫 등장 순서 보존: 카탈로그 순서(협회 sort_order → code)의 첫 부서
      expect(labels.first, '남자오픈');
      // 골드부/일반부 등 공통 라벨 포함
      expect(labels, contains('골드부'));
      expect(labels, contains('일반부'));
      expect(labels, contains('여자우승자부'));
    });

    test('골드부 라벨 → 협회 무관 모든 골드부 코드', () {
      final codes = tennisCodesForLabel('골드부');
      expect(codes, containsAll(['gj_m_gold', 'jn_m_gold']));
      expect(codes.every((c) => c.endsWith('_gold')), isTrue);
    });

    test('미등록 라벨은 빈 리스트', () {
      expect(tennisCodesForLabel('존재하지않는부'), isEmpty);
    });

    test('tennisCodesForLabels 는 여러 라벨 코드를 합집합으로 모음', () {
      final codes = tennisCodesForLabels({'골드부', '일반부'});
      expect(codes, containsAll(['gj_m_gold', 'jn_m_gold']));
      expect(codes, containsAll(['gj_m_general', 'jn_m_general']));
      // 중복 없는 Set
      expect(codes.length, codes.toSet().length);
    });

    test('빈 라벨 집합 → 빈 코드 집합', () {
      expect(tennisCodesForLabels(const <String>{}), isEmpty);
    });

    test('모든 division 코드는 라벨 그룹핑으로 왕복 가능', () {
      // 각 코드는 자기 라벨의 코드 집합에 반드시 포함된다.
      for (final d in tennisDivisions) {
        expect(tennisCodesForLabel(d.label), contains(d.code));
      }
    });
  });

  group('org-scoped division helpers', () {
    test('tennisDivisionLabelsForOrg(gj) → 광주 부서 라벨만, 첫 등장 순서', () {
      final labels = tennisDivisionLabelsForOrg('gj');
      // gj 그룹 안에서는 code 순 — DB 가 order('code') 로 주는 순서와 같다.
      expect(labels.first, '초급자부');
      expect(labels, contains('골드부'));
      expect(labels, contains('지도자부'));
      // 유니크
      expect(labels.toSet().length, labels.length);
      // gj 전용: gj division 의 라벨 집합과 일치
      final gjLabels = divisionsForOrg('gj').map((d) => d.label).toSet();
      expect(labels.toSet(), gjLabels);
    });

    test('rankingGradesForOrg(gj) → 대회 종목 전용은 빠진다', () {
      final codes = rankingGradesForOrg('gj').map((d) => d.code).toList();
      expect(codes, containsAll(['gj_m_open', 'gj_m_gold', 'gj_w_rookie']));
      // 초급자부는 경력 기준 별도 대회, 마스터즈부·지동부는 대회만 있고 등급이 아니다.
      expect(codes, isNot(contains('gj_m_beginner')));
      expect(codes, isNot(contains('gj_m_masters')));
      expect(codes, isNot(contains('gj_m_jidong')));
    });

    test('divisionsForOrg(gj) 는 종목 전용까지 전부 준다 — 대회 제보용', () {
      // 온보딩 필터를 여기까지 번지게 하면 초급자부·마스터즈부 대회를 제보할 수 없게 된다.
      final codes = divisionsForOrg('gj').map((d) => d.code).toList();
      expect(codes, containsAll(['gj_m_beginner', 'gj_m_masters', 'gj_m_open']));
    });

    test('tennisDivisionLabelsForOrg(kata) → 부수제 1~5부/여자부', () {
      final labels = tennisDivisionLabelsForOrg('kata');
      expect(labels, ['1부', '2부', '3부', '4부', '5부', '여자부']);
    });

    test('미등록 org → 빈 리스트', () {
      expect(tennisDivisionLabelsForOrg('nope'), isEmpty);
    });

    test('tennisCodesForLabelInOrg(gj, 골드부) → gj_m_gold 만 (jn 제외)', () {
      final codes = tennisCodesForLabelInOrg('gj', '골드부');
      expect(codes, ['gj_m_gold']);
      expect(codes, isNot(contains('jn_m_gold')));
    });

    test('tennisCodesForLabelInOrg(jn, 골드부) → jn_m_gold 만', () {
      expect(tennisCodesForLabelInOrg('jn', '골드부'), ['jn_m_gold']);
    });

    test('해당 org 에 없는 라벨 → 빈 리스트', () {
      // 골드부는 gj/jn 부서라 kta 에 없다
      expect(tennisCodesForLabelInOrg('kta', '골드부'), isEmpty);
    });

    test('tennisCodesForLabelsInOrg → org 스코프 합집합', () {
      final codes = tennisCodesForLabelsInOrg('gj', {'골드부', '일반부'});
      expect(codes, containsAll(['gj_m_gold', 'gj_m_general']));
      expect(codes, isNot(contains('jn_m_gold')));
    });

    test('org 스코프 union 은 전 협회 union 의 부분집합', () {
      final gjGold = tennisCodesForLabelInOrg('gj', '골드부').toSet();
      final allGold = tennisCodesForLabel('골드부').toSet();
      expect(allGold.containsAll(gjGold), isTrue);
      expect(gjGold.length, lessThan(allGold.length));
    });
  });

  group('DivisionCatalog DB load', () {
    setUp(() => DivisionCatalog.instance.reset());
    tearDown(() {
      DivisionCatalog.instance.reset();
      OrgCatalog.instance.reset();
    });

    test('미로드 시 all()은 const fallback 반환 — DB 정본과 같은 목록', () {
      expect(DivisionCatalog.instance.isLoaded, isFalse);
      // 폴백은 이제 DB 전량의 사본이다(check_division_parity.py 가 강제). 예전엔 kato 가
      // 통째로 빠져 있어 오프라인에서 코드 원문이 노출됐다.
      expect(DivisionCatalog.instance.all.where((d) => d.org == 'kato'),
          isNotEmpty);
      expect(DivisionCatalog.instance.all.map((d) => d.code),
          containsAll(['kato_gaenari', 'gj_m_open', 'kta_m_open']));
    });

    test('미로드 시에도 divisionLabel(kato_*)이 라벨을 준다', () {
      // 스플래시 게이트(JY-121)가 늦거나 로드가 실패해도 코드 원문이 새지 않는다.
      expect(divisionLabel('kato_gaenari'), '개나리부');
    });

    test('ingestRows 후 kato 라벨 해석', () {
      DivisionCatalog.instance.ingestRows([
        {
          'code': 'kato_gaenari',
          'org_code': 'kato',
          'label_ko': '개나리부',
          'gender': 'female',
        },
        {
          'code': 'kato_masters',
          'org_code': 'kato',
          'label_ko': '마스터스부',
          'gender': 'all',
        },
      ]);
      expect(DivisionCatalog.instance.isLoaded, isTrue);
      expect(divisionLabel('kato_gaenari'), '개나리부');
      expect(divisionLabel('kato_masters'), '마스터스부');
      // 로드 성공 시 완전 교체: fallback gj 부서는 더 이상 없음
      expect(DivisionCatalog.instance.all.where((d) => d.org == 'gj'), isEmpty);
      expect(tennisDivisionLabelsForOrg('kato'), ['개나리부', '마스터스부']);
    });

    // check_division_parity.py 가 DB 와 대조하는 JSON 스냅샷이 이 폴백과 같은지 확인한다.
    // 다리의 반대쪽 — 마이그레이션에서 분류를 하나 빠뜨리거나 폴백에서 코드를 지우면
    // 둘 중 하나가 반드시 빨간불이 된다(codex: 기존 '왕복' 테스트는 목록 자체를 순회해
    // 삭제된 코드가 검사 대상에서 함께 사라지므로 조용히 약해진다).
    test('폴백 전체가 JSON 스냅샷과 순서·값 모두 일치한다(스냅샷 다리)', () {
      DivisionCatalog.instance.reset();
      final snapshot = jsonDecode(
        File('test/fixtures/division_fallback.json').readAsStringSync(),
      ) as List<dynamic>;
      final actual = DivisionCatalog.instance.fallbackSnapshot
          .map((d) => {
                'code': d.code,
                'org': d.org,
                'label': d.label,
                'isRankingGrade': d.isRankingGrade,
                'isActive': d.isActive,
              })
          .toList();
      expect(actual, snapshot);
    });

    test('비활성 부서는 목록에서 빠지되 라벨 해석은 된다', () {
      DivisionCatalog.instance.reset();
      // 과거 대회 상세에 'ktfs_open' 같은 코드 원문이 뜨면 안 된다.
      expect(divisionLabel('ktfs_open'), '오픈');
      expect(divisionLabel('local_w'), '자체 여자부');
      expect(tennisDivisions.map((d) => d.code), isNot(contains('ktfs_open')));
      expect(divisionsForOrg('ktfs'), isEmpty);
    });

    test('ingestRows 가 is_ranking_grade 를 반영하고, 없으면 등급으로 본다', () {
      DivisionCatalog.instance.ingestRows([
        {
          'code': 'gj_m_open',
          'org_code': 'gj',
          'label_ko': '오픈부',
          'gender': 'male',
          'is_ranking_grade': true,
        },
        {
          'code': 'gj_m_masters',
          'org_code': 'gj',
          'label_ko': '마스터즈부',
          'gender': 'male',
          'is_ranking_grade': false,
        },
        // 컬럼이 없는 구버전 응답 → 기존 동작대로 등급으로 본다.
        {'code': 'gj_m_gold', 'org_code': 'gj', 'label_ko': '골드부', 'gender': 'male'},
      ]);
      expect(rankingGradesForOrg('gj').map((d) => d.code),
          ['gj_m_open', 'gj_m_gold']);
      // 라벨 해석은 종목 전용도 된다 — 대회 화면이 이름을 잃으면 안 된다.
      expect(divisionLabel('gj_m_masters'), '마스터즈부');
    });

    test('ingestRows 도 비활성은 목록에서 빼고 라벨은 남긴다(DB 로드 경로)', () {
      // 폴백 경로만 검증하면 파서 회귀를 놓친다(codex).
      DivisionCatalog.instance.ingestRows([
        {
          'code': 'gj_m_open',
          'org_code': 'gj',
          'label_ko': '오픈부',
          'gender': 'male',
          'is_active': true,
        },
        {
          'code': 'ktfs_open',
          'org_code': 'ktfs',
          'label_ko': '오픈',
          'gender': 'all',
          'is_active': false,
        },
      ]);
      expect(tennisDivisions.map((d) => d.code), ['gj_m_open']);
      expect(divisionLabel('ktfs_open'), '오픈');
    });

    test('ingestRows 는 org 우선순위(tennisOrgs 순서)로 그룹핑, 그룹 내 입력순 보존', () {
      // 입력을 뒤섞어 넣어도 kta < gj < kato 순서(tennisOrgs)로 그룹핑돼야 함
      DivisionCatalog.instance.ingestRows([
        {'code': 'gj_b', 'org_code': 'gj', 'label_ko': 'GJ-B', 'gender': 'all'},
        {'code': 'kato_a', 'org_code': 'kato', 'label_ko': 'KATO-A', 'gender': 'all'},
        {'code': 'kta_a', 'org_code': 'kta', 'label_ko': 'KTA-A', 'gender': 'all'},
        {'code': 'gj_a', 'org_code': 'gj', 'label_ko': 'GJ-A', 'gender': 'all'},
      ]);
      final orgs = DivisionCatalog.instance.all.map((d) => d.org).toList();
      // tennisOrgs: kta 가 kato 보다, kato 가 gj 보다 앞
      expect(orgs, ['kta', 'kato', 'gj', 'gj']);
      // gj 그룹 내부는 입력 순서(gj_b, gj_a) 보존
      final gjCodes = DivisionCatalog.instance.all
          .where((d) => d.org == 'gj')
          .map((d) => d.code)
          .toList();
      expect(gjCodes, ['gj_b', 'gj_a']);
    });

    test('부서 그룹 순서는 OrgCatalog 순서를 따른다(DB sort_order 반영)', () {
      // 협회 순서를 뒤집어 로드하면 부서 그룹 순서도 따라 뒤집혀야 한다.
      OrgCatalog.instance.ingestRows([
        {'code': 'gj', 'label_ko': '광주', 'short_label': '광주협회',
         'name_ko': '광주', 'is_active': true, 'sort_order': 10},
        {'code': 'kta', 'label_ko': 'KTA', 'short_label': 'KTA',
         'name_ko': 'KTA', 'is_active': true, 'sort_order': 20},
      ]);
      DivisionCatalog.instance.ingestRows([
        {'code': 'kta_a', 'org_code': 'kta', 'label_ko': 'KTA-A', 'gender': 'all'},
        {'code': 'gj_a', 'org_code': 'gj', 'label_ko': 'GJ-A', 'gender': 'all'},
      ]);
      final orgs = DivisionCatalog.instance.all.map((d) => d.org).toList();
      expect(orgs, ['gj', 'kta']); // OrgCatalog 순서(gj 가 앞)
    });

    test('비활성 협회의 부서도 카탈로그 순서를 지킨다(뒤로 밀리지 않음)', () {
      OrgCatalog.instance.ingestRows([
        {'code': 'ktfs', 'label_ko': 'KTFS', 'short_label': 'KTFS',
         'name_ko': 'KTFS', 'is_active': false, 'sort_order': 10},
        {'code': 'kta', 'label_ko': 'KTA', 'short_label': 'KTA',
         'name_ko': 'KTA', 'is_active': true, 'sort_order': 20},
      ]);
      DivisionCatalog.instance.ingestRows([
        {'code': 'kta_a', 'org_code': 'kta', 'label_ko': 'KTA-A', 'gender': 'all'},
        {'code': 'ktfs_a', 'org_code': 'ktfs', 'label_ko': 'KTFS-A', 'gender': 'all'},
      ]);
      // ktfs 는 비활성이지만 sort_order 10 이라 kta(20)보다 앞이어야 한다.
      // 활성 목록(tennisOrgs)만 보면 ktfs 가 unknown 으로 빠져 뒤로 밀린다.
      expect(DivisionCatalog.instance.all.map((d) => d.org).toList(),
          ['ktfs', 'kta']);
    });

    test('reset 후 다시 fallback 으로 복귀', () {
      DivisionCatalog.instance.ingestRows([
        {'code': 'kato_gaenari', 'org_code': 'kato', 'label_ko': '개나리부', 'gender': 'female'},
      ]);
      expect(DivisionCatalog.instance.isLoaded, isTrue);
      DivisionCatalog.instance.reset();
      expect(DivisionCatalog.instance.isLoaded, isFalse);
      // 폴백으로 복귀 — 폴백도 kato 를 들고 있으므로 라벨은 그대로 나온다.
      expect(divisionLabel('kato_gaenari'), '개나리부');
    });

    // JY-121: 스플래시 게이트가 이 Future 를 기다려 stale fallback 을 예방한다.
    test('whenReady 는 준비 전 미완료, ingest 후 완료된다', () async {
      var ready = false;
      unawaited(DivisionCatalog.instance.whenReady.then((_) => ready = true));
      await pumpEventQueue();
      expect(ready, isFalse);
      DivisionCatalog.instance.ingestRows([
        {'code': 'kato_gaenari', 'org_code': 'kato', 'label_ko': '개나리부', 'gender': 'female'},
      ]);
      await pumpEventQueue();
      expect(ready, isTrue);
    });

    test('reset 후 whenReady 는 미완료로 재무장된다', () async {
      DivisionCatalog.instance.ingestRows([
        {'code': 'kato_gaenari', 'org_code': 'kato', 'label_ko': '개나리부', 'gender': 'female'},
      ]);
      await pumpEventQueue();
      DivisionCatalog.instance.reset();
      var ready = false;
      unawaited(DivisionCatalog.instance.whenReady.then((_) => ready = true));
      await pumpEventQueue();
      expect(ready, isFalse);
    });
  });

  group('OrgCatalog', () {
    tearDown(() => OrgCatalog.instance.reset());

    // #330: check_org_parity.py 가 DB 와 대조하는 JSON 스냅샷(test/fixtures/org_fallback.json)이
    // 이 폴백과 같은지 여기서 확인한다. Dart 소스를 정규식으로 파싱하면 주석·이스케이프·
    // 공백 변형에 사각지대가 계속 생긴다(codex 재발 3회) — 실제 Dart 코드가 만든 값과
    // 비교하면 문법 파싱이 아예 필요 없다.
    test('폴백 전체가 JSON 스냅샷과 순서·값 모두 일치한다(스냅샷 다리, #330)', () {
      OrgCatalog.instance.reset();
      final snapshot = jsonDecode(
        File('test/fixtures/org_fallback.json').readAsStringSync(),
      ) as List<dynamic>;
      final actual = OrgCatalog.instance.all
          .map((e) => {
                'code': e.code,
                'label': e.label,
                'shortLabel': e.shortLabel,
                'isActive': e.isActive,
              })
          .toList();
      expect(actual, snapshot);
    });

    test('미로드 시 폴백 목록·라벨을 쓴다', () {
      expect(OrgCatalog.instance.isLoaded, isFalse);
      expect(tennisOrgs.first, 'kta');
      expect(tennisOrgLabel('kta'), '대한테니스협회 (KTA)');
      expect(tennisOrgShortLabel('gj'), '광주협회');
    });

    test('ingestRows 는 sort_order 순으로 정렬하고 비활성은 목록에서 뺀다', () {
      OrgCatalog.instance.ingestRows([
        {'code': 'jn', 'label_ko': '전남', 'short_label': '전남협회',
         'name_ko': '전라남도테니스협회', 'is_active': true, 'sort_order': 90},
        {'code': 'kta', 'label_ko': 'KTA 라벨', 'short_label': 'KTA',
         'name_ko': '대한테니스협회', 'is_active': true, 'sort_order': 10},
        {'code': 'ktfs', 'label_ko': '폐지협회', 'short_label': 'KTFS',
         'name_ko': '국민생활체육', 'is_active': false, 'sort_order': 40},
      ]);
      expect(tennisOrgs, ['kta', 'jn']); // 비활성 ktfs 제외, sort_order 순
      expect(tennisOrgLabel('kta'), 'KTA 라벨');
    });

    test('비활성 협회도 라벨 조회는 된다(보유자 화면에 코드가 노출되면 안 됨)', () {
      OrgCatalog.instance.ingestRows([
        {'code': 'ktfs', 'label_ko': '국민생활체육 전국테니스연합회 (KTFS)',
         'short_label': 'KTFS', 'name_ko': '국민생활체육', 'is_active': false,
         'sort_order': 40},
      ]);
      expect(tennisOrgs, isNot(contains('ktfs')));
      expect(tennisOrgLabel('ktfs'), '국민생활체육 전국테니스연합회 (KTFS)');
    });

    test('label_ko 가 비면 name_ko 로 폴백한다', () {
      OrgCatalog.instance.ingestRows([
        {'code': 'new1', 'label_ko': null, 'short_label': null,
         'name_ko': '새협회', 'is_active': true, 'sort_order': 1000},
      ]);
      expect(tennisOrgLabel('new1'), '새협회');
      expect(tennisOrgShortLabel('new1'), '새협회');
    });

    test('reset 후 폴백으로 복귀한다', () {
      OrgCatalog.instance.ingestRows([
        {'code': 'kta', 'label_ko': 'X', 'short_label': 'X',
         'name_ko': 'X', 'is_active': true, 'sort_order': 10},
      ]);
      expect(OrgCatalog.instance.isLoaded, isTrue);
      OrgCatalog.instance.reset();
      expect(OrgCatalog.instance.isLoaded, isFalse);
      expect(tennisOrgLabel('kta'), '대한테니스협회 (KTA)');
    });

    // JY-135 codex P1-1: 폴백의 ktfs 가 isActive:true 였을 때 DB(is_active=false)와
    // 어긋나 온라인/오프라인에서 KTFS 노출 여부가 달라졌다.
    test('폴백 ktfs 는 비활성 — DB 백필과 일치해야 온오프라인 동작이 같다', () {
      expect(OrgCatalog.instance.isLoaded, isFalse);
      expect(tennisOrgs, isNot(contains('ktfs')),
          reason: 'ktfs 는 DB 에서 is_active=false 다');
      // 비활성이어도 라벨 조회는 여전히 동작해야 한다(기존 사용자 화면 보호).
      expect(tennisOrgLabel('ktfs'), '국민생활체육 전국테니스연합회 (KTFS)');
    });
  });

  group('tennisOrgsWithDivisions (JY-135 P1-2)', () {
    tearDown(() {
      OrgCatalog.instance.reset();
      DivisionCatalog.instance.reset();
    });

    test('부서가 0개인 협회는 빠지고 부서가 있는 협회만 남는다', () {
      OrgCatalog.instance.ingestRows([
        {'code': 'kta', 'label_ko': 'KTA', 'short_label': 'KTA',
         'name_ko': 'KTA', 'is_active': true, 'sort_order': 10},
        {'code': 'kssta', 'label_ko': 'KSSTA', 'short_label': 'KSSTA',
         'name_ko': 'KSSTA', 'is_active': true, 'sort_order': 20},
      ]);
      DivisionCatalog.instance.ingestRows([
        {'code': 'kta_a', 'org_code': 'kta', 'label_ko': 'KTA-A', 'gender': 'all'},
      ]);
      // kssta 는 부서가 없어 골랐을 때 부서 칩이 하나도 없어 제보를 끝낼 수 없다.
      expect(tennisOrgsWithDivisions, ['kta']);
      expect(tennisOrgsWithDivisions, isNot(contains('kssta')));
    });

    test('부서가 생기면(INSERT) 자동으로 선택지에 나타난다', () {
      OrgCatalog.instance.ingestRows([
        {'code': 'kssta', 'label_ko': 'KSSTA', 'short_label': 'KSSTA',
         'name_ko': 'KSSTA', 'is_active': true, 'sort_order': 20},
      ]);
      DivisionCatalog.instance.ingestRows([]);
      expect(tennisOrgsWithDivisions, isEmpty);

      DivisionCatalog.instance.ingestRows([
        {'code': 'kssta_a', 'org_code': 'kssta', 'label_ko': 'KSSTA-A', 'gender': 'all'},
      ]);
      expect(tennisOrgsWithDivisions, ['kssta']);
    });
  });

  group('랭킹 미러 보유 협회', () {
    // 등록은 되지만 본인 연결·개인 기록장이 안 열리는 협회를 가른다.
    // 온보딩 안내와 랭킹 화면 탭이 같은 목록을 본다 — 미러를 늘릴 때 고칠 곳은
    // kRankingDivisions 하나뿐이어야 한다.
    test('미러가 있는 협회는 광주·전남뿐이다', () {
      expect(kRankingDivisions.keys.toSet(), {'gj', 'jn'});
      expect(orgHasRankingMirror('gj'), isTrue);
      expect(orgHasRankingMirror('jn'), isTrue);
    });

    test('전국 협회·시군클럽은 미러가 없다', () {
      // 2026-08-18 프로덕션 실측: 유저가 등록한 협회에 kta·kata 가 있는데
      // org_rankings 에는 gj·jn 행만 있다.
      for (final org in ['kta', 'kata', 'kato', 'kstf', 'kasta', 'kssta',
        'local', 'ktfs']) {
        expect(orgHasRankingMirror(org), isFalse, reason: org);
      }
    });

    test('미러 협회의 부서는 전부 그 협회 접두사를 쓴다', () {
      // 접두사가 어긋나면 랭킹 화면이 빈 표를 띄운다(org_code+division_code 조회).
      kRankingDivisions.forEach((org, divisions) {
        for (final d in divisions) {
          expect(d, startsWith('${org}_'), reason: '$org / $d');
        }
      });
    });
  });

  group('RegionCatalog', () {
    tearDown(() => RegionCatalog.instance.reset());

    // check_region_parity.py 가 DB 와 대조하는 JSON 스냅샷(test/fixtures/region_fallback.json)이
    // 이 폴백과 같은지 확인한다(협회 #330 과 같은 스냅샷 다리). regions 엔 sort_order 가
    // 없어 표시 순서는 폴백이 정하므로, 순서가 아니라 값을 대조한다 — 양쪽을 code 순으로
    // 정렬해 비교한다(check_region_parity.py 의 DB 쿼리와 같은 규칙).
    test('폴백 전체가 JSON 스냅샷과 값 일치한다(code 순 정렬, 스냅샷 다리)', () {
      RegionCatalog.instance.reset();
      final snapshot = jsonDecode(
        File('test/fixtures/region_fallback.json').readAsStringSync(),
      ) as List<dynamic>;
      final actual = ([...RegionCatalog.instance.fallbackSnapshot]
            ..sort((a, b) => a.code.compareTo(b.code)))
          .map((e) => {
                'code': e.code,
                'label': e.label,
                'isActive': e.isActive,
              })
          .toList();
      expect(actual, snapshot);
    });

    test('미로드 시 폴백 목록·라벨을 쓴다 — 순서는 지도상 순서', () {
      expect(RegionCatalog.instance.isLoaded, isFalse);
      expect(regionCodes.first, 'seoul');
      expect(regionCodes.last, 'jeju');
      expect(regionCodes.length, 17);
      expect(regionLabel('gwangju'), '광주');
    });

    test('ingestRows 는 폴백 순서로 정렬하고 비활성은 목록에서 뺀다', () {
      RegionCatalog.instance.ingestRows([
        {'code': 'gwangju', 'display_name_ko': '광주', 'is_active': true},
        {'code': 'seoul_metro', 'display_name_ko': '수도권', 'is_active': false},
        {'code': 'seoul', 'display_name_ko': '서울', 'is_active': true},
      ]);
      // DB 가 code 순으로 줘도 표시 순서는 폴백(지도상 순서)을 따른다.
      expect(regionCodes, ['seoul', 'gwangju']);
      expect(regionLabel('seoul'), '서울');
    });

    test('폴백에 없는 신규 지역은 목록 끝에 나타난다 — INSERT 만으로 반영', () {
      RegionCatalog.instance.ingestRows([
        {'code': 'dokdo', 'display_name_ko': '독도', 'is_active': true},
        {'code': 'seoul', 'display_name_ko': '서울', 'is_active': true},
      ]);
      expect(regionCodes, ['seoul', 'dokdo']);
      expect(regionLabel('dokdo'), '독도');
    });

    test('비활성(deprecated 묶음 코드)도 라벨 해석은 된다', () {
      // backfill 이전 데이터 화면에 'seoul_metro' 코드 원문이 뜨면 안 된다.
      expect(regionCodes, isNot(contains('seoul_metro')));
      expect(isValidRegionCode('seoul_metro'), isFalse);
      expect(regionLabel('seoul_metro'), '수도권');
      expect(regionLabel('busan_ulsan_gn'), '부산·울산·경남');
    });

    test('빈 응답은 무시한다(권한·필터 사고 방어)', () {
      RegionCatalog.instance.ingestRows([]);
      expect(RegionCatalog.instance.isLoaded, isFalse);
      expect(regionCodes.length, 17);
    });

    test('reset 후 폴백으로 복귀한다', () {
      RegionCatalog.instance.ingestRows([
        {'code': 'seoul', 'display_name_ko': '서울특별시', 'is_active': true},
      ]);
      expect(RegionCatalog.instance.isLoaded, isTrue);
      expect(regionLabel('seoul'), '서울특별시');
      RegionCatalog.instance.reset();
      expect(RegionCatalog.instance.isLoaded, isFalse);
      expect(regionLabel('seoul'), '서울');
    });
  });
}
