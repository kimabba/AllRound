import 'dart:async';

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
      // 첫 등장 순서 보존: 광주(gj) 오픈부가 첫 항목
      expect(labels.first, '오픈부');
      // 골드부/일반부/크로스대회 등 공통 라벨 포함
      expect(labels, contains('골드부'));
      expect(labels, contains('일반부'));
      expect(labels, contains('크로스대회'));
      expect(labels, contains('여자우승자부'));
    });

    test('골드부 라벨 → 협회 무관 모든 골드부 코드', () {
      final codes = tennisCodesForLabel('골드부');
      expect(codes, containsAll(['gj_m_gold', 'jn_m_gold']));
      expect(codes.every((c) => c.endsWith('_gold')), isTrue);
    });

    test('크로스대회 라벨 → gj/jn 크로스 코드', () {
      final codes = tennisCodesForLabel('크로스대회');
      expect(codes, containsAll(['gj_cross', 'jn_cross']));
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
      expect(labels.first, '오픈부');
      expect(labels, contains('골드부'));
      expect(labels, contains('부부부'));
      // 유니크
      expect(labels.toSet().length, labels.length);
      // gj 전용: gj division 의 라벨 집합과 일치
      final gjLabels = divisionsForOrg('gj').map((d) => d.label).toSet();
      expect(labels.toSet(), gjLabels);
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
      // 부부부는 kta 에 없다
      expect(tennisCodesForLabelInOrg('kta', '부부부'), isEmpty);
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
    tearDown(() => DivisionCatalog.instance.reset());

    test('미로드 시 all()은 const fallback 반환', () {
      expect(DivisionCatalog.instance.isLoaded, isFalse);
      // fallback 에는 kato 부서가 없다
      expect(
        DivisionCatalog.instance.all.where((d) => d.org == 'kato'),
        isEmpty,
      );
    });

    test('미로드 시 divisionLabel(kato_*)은 코드 원문 반환', () {
      expect(divisionLabel('kato_gaenari'), 'kato_gaenari');
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

    test('reset 후 다시 fallback 으로 복귀', () {
      DivisionCatalog.instance.ingestRows([
        {'code': 'kato_gaenari', 'org_code': 'kato', 'label_ko': '개나리부', 'gender': 'female'},
      ]);
      expect(DivisionCatalog.instance.isLoaded, isTrue);
      DivisionCatalog.instance.reset();
      expect(DivisionCatalog.instance.isLoaded, isFalse);
      expect(divisionLabel('kato_gaenari'), 'kato_gaenari');
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
}
