# 랭킹 성장 기록(2단계) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 랭킹 표 어느 선수든(연결 여부 무관) 순위 추이 그래프를 보고, 연결된 본인은 "이 시즌 기록"(올해 참가 수·누적 우승·시즌 최고 순위·전적 분포)까지 보는 화면을 랭킹 탭 안에 만든다. MY 화면에서 기록 섹션을 완전히 뗀다.

**Architecture:** 이미 있는 `RecordContent` 위젯(내부: 현재 순위 → 최고의 순간 → 전적 리스트)을 확장 지점으로 삼아 "이 시즌 기록" 블록과 순위 추이 스파크라인을 끼워 넣는다. 이 컴포넌트를 두 곳에서 재사용한다 — 신규 `/rankings/me`(내 기록, 랭킹 탭 진입) 화면과 오늘 만든 선수 상세시트(`player_detail_sheet.dart`). 순위 스냅샷(`org_ranking_snapshots`)은 이미 2026-08-04부터 매일 자동 적재 중이며, 이번 작업은 그 위에 RLS를 열고 조회·표시 레이어만 얹는다.

**Tech Stack:** Flutter, Riverpod(FutureProvider), Supabase(RLS), 커스텀 `CustomPainter`(외부 차트 라이브러리 없음).

## Global Constraints

- 앱이 자체 점수·레벨을 새로 만들지 않는다 — 전부 `org_player_results`/`org_ranking_snapshots`(협회 공표 데이터)에서 파생된 사실만 표시한다.
- `resultRound`가 null(정규화 실패)인 행은 원문(`resultRaw`)을 그대로 보여주거나 "기타"로만 묶는다. 추측값·0으로 채우지 않는다.
- RLS 정책은 `to authenticated`를 명시한다 — 생략하면 PUBLIC이 되어 anon 조회가 42501로 죽는다(#365).
- 마이그레이션은 `supabase db push`가 불가능한 상태다(JY-116) — 파일은 repo에 남기고, 적용은 Supabase MCP `execute_sql`로 직접 한다.
- Dart 파일 수정 후 `flutter analyze`와 관련 `flutter test`가 깨끗해야 각 태스크가 끝난다.

---

## 파일 구조

| 파일 | 상태 | 책임 |
|---|---|---|
| `supabase/migrations/20260810130000_org_ranking_snapshots_public_read.sql` | 생성 | `org_ranking_snapshots` RLS를 `org_rankings`/`org_player_results` 수준으로 공개 |
| `app/lib/models/org_ranking_snapshot.dart` | 생성 | 스냅샷 1행 모델 |
| `app/lib/models/season_stats.dart` | 생성 | "이 시즌 기록" 계산(순수 함수) + 전적 분포 라벨 |
| `app/lib/widgets/rankings/rank_trend_sparkline.dart` | 생성 | 순위 추이 커스텀 스파크라인 |
| `app/lib/services/ranking_api.dart` | 수정 | `playerRankingHistory()` 추가 |
| `app/lib/widgets/profile/my_record_widgets.dart` | 수정 | `MyRecordSection` 삭제, `ConnectPrompt`/`RecordMessage`/`RecordSkeleton` 공개 전환, `RecordContent`에 시즌 기록·추이 블록 추가 |
| `app/lib/state/providers.dart` | 수정 | `myRankingHistoryProvider` 추가 |
| `app/lib/screens/rankings/my_record_screen.dart` | 생성 | `/rankings/me` 화면 |
| `app/lib/router.dart` | 수정 | `/rankings/me` 라우트 + `_untabbedPaths` 등록 |
| `app/lib/screens/rankings/rankings_screen.dart` | 수정 | "내 기록 보기" 진입 버튼 |
| `app/lib/screens/profile_screen.dart` | 수정 | `MyRecordSection` 호출 제거 |
| `app/lib/widgets/rankings/player_detail_sheet.dart` | 수정 | 스냅샷도 fetch해 `RecordContent`에 전달 |
| `app/test/models/org_ranking_snapshot_test.dart` | 생성 | 모델 fromJson |
| `app/test/models/season_stats_test.dart` | 생성 | 통계 계산 순수 함수 |
| `app/test/widgets/rank_trend_sparkline_test.dart` | 생성 | 스파크라인 위젯 |
| `app/test/widgets/my_record_section_test.dart` → `app/test/widgets/record_content_test.dart` | 이름 변경 + 확장 | `RecordContent`가 이제 시즌 기록·추이도 검증 |

---

### Task 1: `OrgRankingSnapshot` 모델

**Files:**
- Create: `app/lib/models/org_ranking_snapshot.dart`
- Test: `app/test/models/org_ranking_snapshot_test.dart`

**Interfaces:**
- Produces: `OrgRankingSnapshot` (필드: `orgCode String`, `divisionCode String`, `orgPlayerId String`, `capturedOn DateTime`, `rank int`, `totalPoints int`), `OrgRankingSnapshot.fromJson(Map<String, dynamic>)`.

- [ ] **Step 1: Write the failing test**

`app/test/models/org_ranking_snapshot_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:allround/models/org_ranking_snapshot.dart';

void main() {
  test('fromJson이 스냅샷 한 행을 그대로 옮긴다', () {
    final s = OrgRankingSnapshot.fromJson({
      'org_code': 'gj',
      'division_code': 'gj_m_gold',
      'org_player_id': 'vudghk2116',
      'captured_on': '2026-08-04',
      'rank': 1,
      'total_points': 2649,
    });

    expect(s.orgCode, 'gj');
    expect(s.divisionCode, 'gj_m_gold');
    expect(s.orgPlayerId, 'vudghk2116');
    expect(s.capturedOn, DateTime.parse('2026-08-04'));
    expect(s.rank, 1);
    expect(s.totalPoints, 2649);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/models/org_ranking_snapshot_test.dart`
Expected: FAIL — `package:allround/models/org_ranking_snapshot.dart` 파일이 없어 컴파일 에러.

- [ ] **Step 3: Write the model**

`app/lib/models/org_ranking_snapshot.dart`:
```dart
/// 부서 내 순위·포인트의 하루 스냅샷. 실명을 담지 않는다 — org_player_id 만.
/// 표시할 때는 org_rankings 의 현재 명단(이름)과 조인해 쓴다.
class OrgRankingSnapshot {
  const OrgRankingSnapshot({
    required this.orgCode,
    required this.divisionCode,
    required this.orgPlayerId,
    required this.capturedOn,
    required this.rank,
    required this.totalPoints,
  });

  final String orgCode;
  final String divisionCode;
  final String orgPlayerId;
  final DateTime capturedOn;
  final int rank;
  final int totalPoints;

  factory OrgRankingSnapshot.fromJson(Map<String, dynamic> j) {
    return OrgRankingSnapshot(
      orgCode: j['org_code'] as String,
      divisionCode: j['division_code'] as String,
      orgPlayerId: j['org_player_id'] as String,
      capturedOn: DateTime.parse(j['captured_on'] as String),
      rank: j['rank'] as int,
      totalPoints: j['total_points'] as int,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/models/org_ranking_snapshot_test.dart`
Expected: PASS (1 test)

- [ ] **Step 5: Commit**

```bash
git add app/lib/models/org_ranking_snapshot.dart app/test/models/org_ranking_snapshot_test.dart
git commit -m "feat(ranking): OrgRankingSnapshot 모델 추가"
```

---

### Task 2: `SeasonStats` 계산 (순수 함수)

**Files:**
- Create: `app/lib/models/season_stats.dart`
- Test: `app/test/models/season_stats_test.dart`

**Interfaces:**
- Consumes: `PlayerResult`(`app/lib/models/player_result.dart` — 필드 `playedOn DateTime`, `resultRound int?`, 이미 존재), `OrgRankingSnapshot`(Task 1의 `rank int`, `orgPlayerId` 등).
- Produces: `SeasonStats`(필드: `tournamentsThisYear int`, `careerWins int`, `seasonBestRank int?`, `resultDistribution Map<int?, int>`), `SeasonStats.compute({required results, required snapshots, required currentYear})`, 최상위 함수 `String seasonDistributionLabel(int? resultRound)`.

- [ ] **Step 1: Write the failing tests**

`app/test/models/season_stats_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:allround/models/org_ranking_snapshot.dart';
import 'package:allround/models/player_result.dart';
import 'package:allround/models/season_stats.dart';

PlayerResult _r({required String on, int? round, int points = 0}) =>
    PlayerResult.fromJson({
      'org_code': 'gj',
      'org_player_id': 'a',
      'tournament_name': 'x',
      'played_on': on,
      'result_raw': round?.toString() ?? '예선탈락',
      'result_round': round,
      'points': points,
    });

OrgRankingSnapshot _s({required String on, required int rank}) =>
    OrgRankingSnapshot.fromJson({
      'org_code': 'gj',
      'division_code': 'gj_m_gold',
      'org_player_id': 'a',
      'captured_on': on,
      'rank': rank,
      'total_points': 1000,
    });

void main() {
  group('SeasonStats.compute', () {
    test('빈 입력이면 전부 0/없음이다', () {
      final stats = SeasonStats.compute(
        results: const [],
        snapshots: const [],
        currentYear: 2026,
      );
      expect(stats.tournamentsThisYear, 0);
      expect(stats.careerWins, 0);
      expect(stats.seasonBestRank, isNull);
      expect(stats.resultDistribution, isEmpty);
    });

    test('올해 참가만 세고 작년 참가는 제외한다', () {
      final stats = SeasonStats.compute(
        results: [
          _r(on: '2026-01-01', round: 4),
          _r(on: '2025-12-31', round: 4),
        ],
        snapshots: const [],
        currentYear: 2026,
      );
      expect(stats.tournamentsThisYear, 1);
    });

    test('resultRound가 1인 행만 우승으로 세고, 연도와 무관하게 누적한다', () {
      final stats = SeasonStats.compute(
        results: [
          _r(on: '2026-01-01', round: 1),
          _r(on: '2025-01-01', round: 1),
          _r(on: '2026-02-01', round: 2),
        ],
        snapshots: const [],
        currentYear: 2026,
      );
      expect(stats.careerWins, 2);
    });

    test('가장 낮은(=가장 좋은) 순위를 시즌 최고로 뽑는다', () {
      final stats = SeasonStats.compute(
        results: const [],
        snapshots: [
          _s(on: '2026-08-04', rank: 12),
          _s(on: '2026-08-05', rank: 3),
          _s(on: '2026-08-06', rank: 7),
        ],
        currentYear: 2026,
      );
      expect(stats.seasonBestRank, 3);
    });

    test('resultRound가 null인 행은 null 키로 묶인다', () {
      final stats = SeasonStats.compute(
        results: [
          _r(on: '2026-01-01', round: null),
          _r(on: '2026-01-02', round: null),
          _r(on: '2026-01-03', round: 1),
        ],
        snapshots: const [],
        currentYear: 2026,
      );
      expect(stats.resultDistribution[null], 2);
      expect(stats.resultDistribution[1], 1);
    });
  });

  group('seasonDistributionLabel', () {
    test('1=우승, 2=준우승, 그 외 정수=N강, null=기타', () {
      expect(seasonDistributionLabel(1), '우승');
      expect(seasonDistributionLabel(2), '준우승');
      expect(seasonDistributionLabel(4), '4강');
      expect(seasonDistributionLabel(null), '기타');
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/models/season_stats_test.dart`
Expected: FAIL — `season_stats.dart` 없음.

- [ ] **Step 3: Write the implementation**

`app/lib/models/season_stats.dart`:
```dart
import 'org_ranking_snapshot.dart';
import 'player_result.dart';

/// 대회 참가·우승·최고 순위·전적 분포를 하나로 묶은 "이 시즌 기록" 요약.
/// org_player_results/org_ranking_snapshots 에서 파생된 사실만 담는다 —
/// 앱이 새 점수·레벨을 만들지 않는다.
class SeasonStats {
  const SeasonStats({
    required this.tournamentsThisYear,
    required this.careerWins,
    required this.seasonBestRank,
    required this.resultDistribution,
  });

  final int tournamentsThisYear;
  final int careerWins;
  final int? seasonBestRank;

  /// key: result_round(1=우승, 2=준우승, 4=4강 …). null 은 정규화 실패(원문만 있음).
  final Map<int?, int> resultDistribution;

  factory SeasonStats.compute({
    required List<PlayerResult> results,
    required List<OrgRankingSnapshot> snapshots,
    required int currentYear,
  }) {
    final tournamentsThisYear =
        results.where((r) => r.playedOn.year == currentYear).length;
    final careerWins = results.where((r) => r.resultRound == 1).length;

    int? seasonBestRank;
    for (final s in snapshots) {
      if (seasonBestRank == null || s.rank < seasonBestRank) {
        seasonBestRank = s.rank;
      }
    }

    final distribution = <int?, int>{};
    for (final r in results) {
      distribution.update(r.resultRound, (v) => v + 1, ifAbsent: () => 1);
    }

    return SeasonStats(
      tournamentsThisYear: tournamentsThisYear,
      careerWins: careerWins,
      seasonBestRank: seasonBestRank,
      resultDistribution: distribution,
    );
  }
}

/// 전적 분포 칩에 쓰는 라벨. [PlayerResult.resultLabel] 과 달리 원문(resultRaw)이
/// 없다 — 집계값이라 특정 대회 하나를 가리키지 않는다.
String seasonDistributionLabel(int? resultRound) => switch (resultRound) {
      1 => '우승',
      2 => '준우승',
      final int n => '$n강',
      null => '기타',
    };
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/models/season_stats_test.dart`
Expected: PASS (6 tests)

- [ ] **Step 5: Commit**

```bash
git add app/lib/models/season_stats.dart app/test/models/season_stats_test.dart
git commit -m "feat(ranking): 이 시즌 기록 통계 계산(SeasonStats) 추가"
```

---

### Task 3: 순위 추이 스파크라인 위젯

**Files:**
- Create: `app/lib/widgets/rankings/rank_trend_sparkline.dart`
- Test: `app/test/widgets/rank_trend_sparkline_test.dart`

**Interfaces:**
- Consumes: `OrgRankingSnapshot`(Task 1).
- Produces: `RankTrendSparkline({required List<OrgRankingSnapshot> snapshots})` — 2개 미만이면 안내 문구, 2개 이상이면 `CustomPaint` 그래프.

- [ ] **Step 1: Write the failing tests**

`app/test/widgets/rank_trend_sparkline_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:allround/models/org_ranking_snapshot.dart';
import 'package:allround/theme/app_theme.dart';
import 'package:allround/widgets/rankings/rank_trend_sparkline.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: child),
    );

OrgRankingSnapshot _s({required String on, required int rank}) =>
    OrgRankingSnapshot.fromJson({
      'org_code': 'gj',
      'division_code': 'gj_m_gold',
      'org_player_id': 'a',
      'captured_on': on,
      'rank': rank,
      'total_points': 1000,
    });

void main() {
  testWidgets('점이 0개면 안내 문구를 보여주고 그래프는 안 그린다', (tester) async {
    await tester.pumpWidget(_wrap(const RankTrendSparkline(snapshots: [])));
    expect(find.text('추이를 보려면 며칠 더 필요해요'), findsOneWidget);
    expect(find.byType(CustomPaint), findsNothing);
  });

  testWidgets('점이 1개여도 안내 문구를 보여준다', (tester) async {
    await tester.pumpWidget(_wrap(RankTrendSparkline(
      snapshots: [_s(on: '2026-08-04', rank: 5)],
    )));
    expect(find.text('추이를 보려면 며칠 더 필요해요'), findsOneWidget);
  });

  testWidgets('점이 2개 이상이면 그래프를 그리고 안내 문구는 사라진다', (tester) async {
    await tester.pumpWidget(_wrap(RankTrendSparkline(
      snapshots: [
        _s(on: '2026-08-04', rank: 5),
        _s(on: '2026-08-05', rank: 3),
      ],
    )));
    expect(find.text('추이를 보려면 며칠 더 필요해요'), findsNothing);
    expect(find.byType(CustomPaint), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('모든 순위가 같아도 0나눗셈 없이 그려진다', (tester) async {
    await tester.pumpWidget(_wrap(RankTrendSparkline(
      snapshots: [
        _s(on: '2026-08-04', rank: 5),
        _s(on: '2026-08-05', rank: 5),
        _s(on: '2026-08-06', rank: 5),
      ],
    )));
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/widgets/rank_trend_sparkline_test.dart`
Expected: FAIL — `rank_trend_sparkline.dart` 없음.

- [ ] **Step 3: Write the widget**

`app/lib/widgets/rankings/rank_trend_sparkline.dart`:
```dart
import 'package:flutter/material.dart';

import '../../models/org_ranking_snapshot.dart';

/// 순위 추이를 선 하나로 보여주는 가벼운 스파크라인. 점 2개 미만이면
/// 그래프 대신 안내 문구를 보여준다 — 빈 그래프를 그리지 않는다.
class RankTrendSparkline extends StatelessWidget {
  const RankTrendSparkline({super.key, required this.snapshots});

  final List<OrgRankingSnapshot> snapshots;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    if (snapshots.length < 2) {
      return Text(
        '추이를 보려면 며칠 더 필요해요',
        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      );
    }

    return SizedBox(
      height: 80,
      width: double.infinity,
      child: CustomPaint(
        painter: _RankTrendPainter(snapshots: snapshots, lineColor: cs.primary),
      ),
    );
  }
}

class _RankTrendPainter extends CustomPainter {
  _RankTrendPainter({required this.snapshots, required this.lineColor});

  final List<OrgRankingSnapshot> snapshots;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final ranks = snapshots.map((s) => s.rank).toList();
    final minRank = ranks.reduce((a, b) => a < b ? a : b);
    final maxRank = ranks.reduce((a, b) => a > b ? a : b);
    final range = maxRank - minRank;

    final path = Path();
    for (var i = 0; i < snapshots.length; i++) {
      final x = size.width * i / (snapshots.length - 1);
      // 낮을수록(1등에 가까울수록) 그래프 위쪽 — y 축 반전.
      final t = range == 0 ? 0.5 : (snapshots[i].rank - minRank) / range;
      final y = t * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RankTrendPainter oldDelegate) =>
      oldDelegate.snapshots != snapshots || oldDelegate.lineColor != lineColor;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/widgets/rank_trend_sparkline_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/rankings/rank_trend_sparkline.dart app/test/widgets/rank_trend_sparkline_test.dart
git commit -m "feat(ranking): 순위 추이 스파크라인 위젯 추가"
```

---

### Task 4: `org_ranking_snapshots` RLS 공개

**Files:**
- Create: `supabase/migrations/20260810130000_org_ranking_snapshots_public_read.sql`

**Interfaces:**
- Produces: DB 정책 `org_ranking_snapshots_read` — `for select to authenticated using (true)`.

- [ ] **Step 1: Write the migration file**

`supabase/migrations/20260810130000_org_ranking_snapshots_public_read.sql`:
```sql
-- 랭킹 성장 기록(2단계) — 순위 스냅샷도 랭킹 표 수준으로 공개
--
-- org_rankings 는 이미 로그인 사용자 전체에 공개(org_rankings_read)이고,
-- 오늘 org_player_results 도 같은 조건으로 열었다(org_player_results_read,
-- 20260810120000). org_ranking_snapshots(순위 추이)만 아직 본인 연결자로
-- 막혀 있어 같은 수준으로 연다.
--
-- 기존 정책(own_select, admin_all)은 그대로 둔다 — RLS 는 OR 로 합쳐지므로
-- 더 넓은 정책을 추가해도 안전하다.

begin;

create policy org_ranking_snapshots_read on public.org_ranking_snapshots
  for select to authenticated
  using (true);

commit;
```

- [ ] **Step 2: Apply directly to production via Supabase MCP**

`supabase db push`는 이 저장소에서 마이그레이션 히스토리 불일치로 쓸 수 없다(JY-116). `execute_sql`로 직접 적용한다:

```sql
create policy org_ranking_snapshots_read on public.org_ranking_snapshots
  for select to authenticated
  using (true);
```

적용 후 확인:
```sql
select policyname, cmd, qual from pg_policies where tablename = 'org_ranking_snapshots';
```
Expected: `org_ranking_snapshots_read` 행이 `qual = 'true'`로 보임(기존 `_own_select`, `_admin_all`과 함께).

- [ ] **Step 3: Commit the migration file**

```bash
git add supabase/migrations/20260810130000_org_ranking_snapshots_public_read.sql
git commit -m "feat(ranking): org_ranking_snapshots RLS를 랭킹 표 수준으로 공개"
```

---

### Task 5: `playerRankingHistory()` API

**Files:**
- Modify: `app/lib/services/ranking_api.dart`

**Interfaces:**
- Consumes: `OrgRankingSnapshot.fromJson`(Task 1), `org_ranking_snapshots_read` RLS(Task 4).
- Produces: `Future<List<OrgRankingSnapshot>> playerRankingHistory({required String orgCode, required String divisionCode, required String orgPlayerId})` — `captured_on` 오름차순.

- [ ] **Step 1: Add the import**

`app/lib/services/ranking_api.dart` 상단(기존 `import '../models/org_ranking.dart';` 바로 아래)에 추가:
```dart
import '../models/org_ranking_snapshot.dart';
```

- [ ] **Step 2: Add the method**

`playerResults()` 메서드(Task 완료 후 파일에서 `Future<List<PlayerResult>> playerResults(...)` 블록) 바로 뒤에 추가:
```dart
  /// 순위 추이(부서 하나). org_ranking_snapshots_read RLS(2026-08-10)로
  /// 로그인 사용자 전체에게 열려 있다. 전 선수가 매일 자동 적재되므로
  /// (연결 여부 무관) 대부분의 선수가 이 데이터를 갖는다.
  Future<List<OrgRankingSnapshot>> playerRankingHistory({
    required String orgCode,
    required String divisionCode,
    required String orgPlayerId,
  }) async {
    final rows = await supabase
        .from('org_ranking_snapshots')
        .select()
        .eq('org_code', orgCode)
        .eq('division_code', divisionCode)
        .eq('org_player_id', orgPlayerId)
        .order('captured_on', ascending: true);
    return List<Map<String, dynamic>>.from(
      rows,
    ).map(OrgRankingSnapshot.fromJson).toList();
  }
```

- [ ] **Step 3: Analyze**

Run: `cd app && flutter analyze lib/services/ranking_api.dart`
Expected: `No issues found!`

이 저장소의 다른 얇은 조회 메서드(`orgRankings`, `playerResults`)와 마찬가지로 네트워크 호출 자체를 단위 테스트하지 않는다 — 이 프로젝트에 Supabase 클라이언트 fake/mock이 없다. 순수 계산 로직(Task 2 `SeasonStats`)만 단위 테스트 대상이다.

- [ ] **Step 4: Commit**

```bash
git add app/lib/services/ranking_api.dart
git commit -m "feat(ranking): playerRankingHistory API 추가"
```

---

### Task 6: `RecordContent` 확장 + `MyRecordSection` 제거

**Files:**
- Modify: `app/lib/widgets/profile/my_record_widgets.dart`
- Rename+Modify: `app/test/widgets/my_record_section_test.dart` → `app/test/widgets/record_content_test.dart`

**Interfaces:**
- Consumes: `SeasonStats.compute`/`seasonDistributionLabel`(Task 2), `RankTrendSparkline`(Task 3), `OrgRankingSnapshot`(Task 1).
- Produces: `RecordContent({required results, rankings = const [], snapshots = const []})`(신규 `snapshots` 파라미터), 공개 위젯 `ConnectPrompt`, `RecordMessage(String)`, `RecordSkeleton`(기존 private `_ConnectPrompt`/`_RecordMessage`/`_RecordSkeleton`를 공개 전환 — Task 8의 `MyRecordScreen`이 이 세 개를 그대로 재사용). `MyRecordSection` 클래스는 삭제.

- [ ] **Step 1: Rewrite the failing/updated test file**

`app/test/widgets/my_record_section_test.dart`을 `app/test/widgets/record_content_test.dart`로 이름을 바꾸고(`git mv`), 기존 5개 테스트는 그대로 두되(모두 `snapshots`를 안 쓰므로 그대로 통과해야 정상) 아래 3개를 추가한다. 최종 파일:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:allround/models/org_ranking.dart';
import 'package:allround/models/org_ranking_snapshot.dart';
import 'package:allround/models/player_result.dart';
import 'package:allround/theme/app_theme.dart';
import 'package:allround/widgets/profile/my_record_widgets.dart';

// AppTheme.light 는 게터가 아니라 메서드다(app/lib/theme/app_theme.dart:9).
// 테마를 빼면 안 된다 — 이 프로젝트 테마가 버튼 폭을 무한으로 강제해서,
// 테마 없이 통과한 위젯이 실기기에서 크래시한 전례가 있다.
Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

PlayerResult _r({
  required String name,
  required String raw,
  int? round,
  required int points,
  required String on,
}) =>
    PlayerResult.fromJson({
      'org_code': 'gj',
      'org_player_id': 'a',
      'tournament_name': name,
      'played_on': on,
      'result_raw': raw,
      'result_round': round,
      'points': points,
    });

OrgRankingRow _rank({required String div, required int rank, required int pts}) =>
    OrgRankingRow.fromJson({
      'org_code': 'gj',
      'division_code': div,
      'rank': rank,
      'player_name': 'zz선수',
      'rank_points': pts,
      'total_points': pts,
    });

OrgRankingSnapshot _snap({required String on, required int rank}) =>
    OrgRankingSnapshot.fromJson({
      'org_code': 'gj',
      'division_code': 'gj_m_gold',
      'org_player_id': 'a',
      'captured_on': on,
      'rank': rank,
      'total_points': 1000,
    });

void main() {
  testWidgets('현재 순위 블록을 보여준다', (tester) async {
    await tester.pumpWidget(_wrap(RecordContent(
      results: const [],
      rankings: [_rank(div: 'gj_m_gold', rank: 12, pts: 1500)],
    )));
    expect(find.textContaining('12'), findsWidgets);
    expect(find.textContaining('1500'), findsWidgets);
  });

  testWidgets('전적이 있으면 최고의 순간과 타임라인을 보여준다', (tester) async {
    await tester.pumpWidget(_wrap(RecordContent(results: [
      _r(name: '광주시장배', raw: '1', round: 1, points: 1000, on: '2026-05-01'),
      _r(name: '봄철대회', raw: '16강', round: 16, points: 60, on: '2026-03-01'),
    ])));
    expect(find.text('광주시장배'), findsWidgets);
    expect(find.text('우승'), findsWidgets);
    expect(find.text('16강'), findsWidgets);
  });

  testWidgets('최고의 순간은 포인트가 가장 높은 대회다', (tester) async {
    await tester.pumpWidget(_wrap(RecordContent(results: [
      _r(name: '작은대회', raw: '4강', round: 4, points: 100, on: '2026-06-01'),
      _r(name: '큰대회', raw: '1', round: 1, points: 1000, on: '2026-05-01'),
    ])));
    final bestCard = find.byKey(const Key('best-moment-card'));
    expect(
      find.descendant(of: bestCard, matching: find.textContaining('큰대회')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bestCard, matching: find.textContaining('작은대회')),
      findsNothing,
    );
  });

  testWidgets('정규화 실패 행은 협회 원문을 그대로 보여준다', (tester) async {
    await tester.pumpWidget(_wrap(RecordContent(results: [
      _r(name: 'zz대회', raw: '예선탈락', round: null, points: 5, on: '2026-05-01'),
    ])));
    expect(find.text('예선탈락'), findsWidgets);
  });

  testWidgets('전적이 없으면 안내를 보여준다', (tester) async {
    await tester.pumpWidget(_wrap(const RecordContent(results: [])));
    expect(find.textContaining('전적'), findsWidgets);
  });

  testWidgets('긴 협회 원문 결과 라벨이 있어도 좁은 화면에서 오버플로우가 나지 않고 잘리지도 않는다',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const raw = '예선탈락(1회전 세트스코어 0:2 패배로 조기 탈락, 재경기 없음)';
    await tester.pumpWidget(_wrap(RecordContent(results: [
      _r(
        name: '전남지사배 전국테니스대회',
        raw: raw,
        round: null,
        points: 5,
        on: '2026-05-01',
      ),
    ])));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final textFinder = find.text(raw);
    expect(textFinder, findsOneWidget);
    final textWidget = tester.widget<Text>(textFinder);
    expect(textWidget.overflow, isNot(TextOverflow.ellipsis));
    expect(textWidget.maxLines, isNull);
  });

  testWidgets('전적이 있으면 이 시즌 기록 카드를 보여준다', (tester) async {
    await tester.pumpWidget(_wrap(RecordContent(
      results: [
        _r(name: '광주시장배', raw: '1', round: 1, points: 1000, on: '2026-05-01'),
      ],
      snapshots: [
        _snap(on: '2026-08-04', rank: 5),
        _snap(on: '2026-08-05', rank: 3),
      ],
    )));
    final statsCard = find.byKey(const Key('season-stats-card'));
    expect(statsCard, findsOneWidget);
    expect(
      find.descendant(of: statsCard, matching: find.textContaining('1개 대회')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: statsCard, matching: find.textContaining('1회')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: statsCard, matching: find.textContaining('3위')),
      findsOneWidget,
    );
  });

  testWidgets('전적이 없으면 이 시즌 기록 카드를 안 보여준다', (tester) async {
    await tester.pumpWidget(_wrap(const RecordContent(results: [])));
    expect(find.byKey(const Key('season-stats-card')), findsNothing);
  });

  testWidgets('전적이 없어도 스냅샷이 있으면 추이 그래프는 보여준다', (tester) async {
    await tester.pumpWidget(_wrap(RecordContent(
      results: const [],
      snapshots: [
        _snap(on: '2026-08-04', rank: 5),
        _snap(on: '2026-08-05', rank: 3),
      ],
    )));
    expect(find.byType(CustomPaint), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run:
```bash
git mv app/test/widgets/my_record_section_test.dart app/test/widgets/record_content_test.dart
cd app && flutter test test/widgets/record_content_test.dart
```
Expected: 새로 추가한 3개(`이 시즌 기록 카드를 보여준다`/`안 보여준다`/`스냅샷이 있으면 추이 그래프`)가 FAIL — `snapshots` 파라미터가 없어 컴파일 에러. 기존 6개는 아직 실행조차 안 됨(같은 파일 컴파일 실패).

- [ ] **Step 3: Rewrite `my_record_widgets.dart`**

전체 파일을 아래로 교체한다:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/org_ranking.dart';
import '../../models/org_ranking_snapshot.dart';
import '../../models/player_result.dart';
import '../../models/season_stats.dart';
import '../../theme/tokens.dart';
import '../../utils/grade_labels.dart'; // divisionLabel, tennisOrgShortLabel
import '../app_card.dart';
import '../rankings/rank_trend_sparkline.dart';

/// 연결 전 — 여기서 막히면 기능 전체가 죽는다. 무엇을 얻는지 먼저 말한다.
class ConnectPrompt extends StatelessWidget {
  const ConnectPrompt({super.key});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return AppCard(
      variant: AppCardVariant.outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('협회 기록을 가져오세요', style: tt.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '협회 랭킹에서 본인을 확인하면 지금까지의 대회 전적이 채워집니다.',
            style: tt.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: () => context.push('/rankings'),
              child: const Text('협회 랭킹에서 찾기'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 연결 후 본문(그리고 다른 선수 상세시트에서도 재사용). 상태를 안 들고
/// 있어 위젯 테스트가 이것만 검증한다.
class RecordContent extends StatelessWidget {
  const RecordContent({
    super.key,
    required this.results,
    this.rankings = const [],
    this.snapshots = const [],
  });

  final List<PlayerResult> results;
  final List<OrgRankingRow> rankings;
  final List<OrgRankingSnapshot> snapshots;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    // 블록 1 "지금" — 현재 순위. 전적이 없어도 이건 보여준다(연결만 되면 나온다).
    final nowBlock = rankings.isEmpty
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...rankings.map((r) => AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${tennisOrgShortLabel(r.orgCode)} · ${divisionLabel(r.divisionCode)}',
                          style: tt.labelLarge,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text('${r.rank}위', style: tt.titleMedium),
                        Text('${r.totalPoints}점', style: tt.bodyLarge),
                      ],
                    ),
                  )),
              const SizedBox(height: AppSpacing.md),
            ],
          );

    // 순위 추이는 전적(results)과 독립이다 — 스냅샷은 연결 여부와 무관하게
    // 전 선수가 매일 자동 적재된다. 전적이 없는 선수도 그래프는 볼 수 있다.
    final trendBlock = snapshots.isEmpty
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RankTrendSparkline(snapshots: snapshots),
              const SizedBox(height: AppSpacing.md),
            ],
          );

    if (results.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          nowBlock,
          trendBlock,
          const RecordMessage('아직 협회에 등록된 전적이 없습니다.'),
        ],
      );
    }

    final best = results.reduce((a, b) => b.points > a.points ? b : a);
    final seasonStats = SeasonStats.compute(
      results: results,
      snapshots: snapshots,
      currentYear: DateTime.now().year,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        nowBlock,
        _SeasonStatsBlock(stats: seasonStats),
        const SizedBox(height: AppSpacing.md),
        trendBlock,
        AppCard(
          key: const Key('best-moment-card'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('최고의 순간', style: tt.labelLarge),
              const SizedBox(height: AppSpacing.xs),
              Text('${best.tournamentName} ${best.resultLabel}', style: tt.titleMedium),
              Text('+${best.points}점', style: tt.bodyLarge),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('전적 ${results.length}건', style: tt.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        ...results.map((r) => _ResultTile(result: r)),
        const SizedBox(height: AppSpacing.sm),
        Text('협회 공표 기준입니다. 앱이 계산한 점수가 아닙니다.', style: tt.bodySmall),
      ],
    );
  }
}

class _SeasonStatsBlock extends StatelessWidget {
  const _SeasonStatsBlock({required this.stats});

  final SeasonStats stats;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final distributionEntries = stats.resultDistribution.entries.toList()
      ..sort((a, b) {
        if (a.key == null) return 1;
        if (b.key == null) return -1;
        return a.key!.compareTo(b.key!);
      });

    return AppCard(
      key: const Key('season-stats-card'),
      variant: AppCardVariant.outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('이 시즌 기록', style: tt.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              _StatItem(label: '올해 참가', value: '${stats.tournamentsThisYear}개 대회'),
              _StatItem(label: '누적 우승', value: '${stats.careerWins}회'),
              if (stats.seasonBestRank != null)
                _StatItem(label: '시즌 최고', value: '${stats.seasonBestRank}위'),
            ],
          ),
          if (distributionEntries.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                for (final e in distributionEntries)
                  Chip(
                    label: Text('${seasonDistributionLabel(e.key)} ${e.value}'),
                    backgroundColor: cs.surfaceContainerHighest,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        Text(value, style: tt.titleMedium),
      ],
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result});

  final PlayerResult result;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final d = result.playedOn;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(result.tournamentName, style: tt.bodyLarge),
                Text(
                  '${d.year}.${d.month}.${d.day}'
                  '${result.eventRaw == null ? '' : ' · ${result.eventRaw}'}',
                  style: tt.bodySmall,
                ),
              ],
            ),
          ),
          Flexible(
            child: Text(result.resultLabel, style: tt.bodyLarge),
          ),
          const SizedBox(width: AppSpacing.md),
          Text('+${result.points}', style: tt.bodyLarge),
        ],
      ),
    );
  }
}

class RecordMessage extends StatelessWidget {
  const RecordMessage(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => AppCard(
        variant: AppCardVariant.outlined,
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
      );
}

class RecordSkeleton extends StatelessWidget {
  const RecordSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const AppCard(
        variant: AppCardVariant.outlined,
        child: SizedBox(height: 96),
      );
}
```

`MyRecordSection` 클래스는 이 파일에서 완전히 빠졌다(다음 태스크들이 그 역할을 `MyRecordScreen`으로 옮긴다).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/widgets/record_content_test.dart`
Expected: PASS (9 tests) — 기존 6개 + 신규 3개.

- [ ] **Step 5: Analyze**

Run: `cd app && flutter analyze lib/widgets/profile/my_record_widgets.dart test/widgets/record_content_test.dart`
Expected: `No issues found!`

주의: 이 시점에 `app/lib/screens/profile_screen.dart`가 아직 `MyRecordSection`을 참조하므로 **프로젝트 전체 analyze는 아직 실패한다** — Task 9에서 해소된다. 이 태스크는 위 두 파일만 분석한다.

- [ ] **Step 6: Commit**

```bash
git add app/lib/widgets/profile/my_record_widgets.dart app/test/widgets/record_content_test.dart
git rm app/test/widgets/my_record_section_test.dart 2>/dev/null || true
git commit -m "feat(ranking): RecordContent에 이 시즌 기록·추이 그래프 추가, MyRecordSection 제거"
```

---

### Task 7: `myRankingHistoryProvider`

**Files:**
- Modify: `app/lib/state/providers.dart`

**Interfaces:**
- Consumes: `myCurrentRankingsProvider`(기존), `apiProvider`(기존), `playerRankingHistory()`(Task 5).
- Produces: `myRankingHistoryProvider` — `FutureProvider<List<OrgRankingSnapshot>>`.

- [ ] **Step 1: Add the import**

`app/lib/state/providers.dart` 상단(`import '../models/org_ranking.dart';` 바로 아래)에 추가:
```dart
import '../models/org_ranking_snapshot.dart';
```

- [ ] **Step 2: Add the provider**

`myCurrentRankingsProvider` 정의 바로 뒤에 추가:
```dart
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
```

- [ ] **Step 3: Analyze**

Run: `cd app && flutter analyze lib/state/providers.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add app/lib/state/providers.dart
git commit -m "feat(ranking): myRankingHistoryProvider 추가"
```

---

### Task 8: `/rankings/me` 화면 + 라우트 + 진입 버튼

**Files:**
- Create: `app/lib/screens/rankings/my_record_screen.dart`
- Modify: `app/lib/router.dart`
- Modify: `app/lib/screens/rankings/rankings_screen.dart`

**Interfaces:**
- Consumes: `myConfirmedLinkProvider`/`myPlayerResultsProvider`/`myCurrentRankingsProvider`(기존), `myRankingHistoryProvider`(Task 7), `ConnectPrompt`/`RecordContent`/`RecordSkeleton`/`RecordMessage`(Task 6).
- Produces: `MyRecordScreen` 위젯, 라우트 `/rankings/me`.

- [ ] **Step 1: Write `MyRecordScreen`**

`app/lib/screens/rankings/my_record_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/profile/my_record_widgets.dart';

/// 랭킹 탭에서 진입하는 "내 기록" 전체 화면. MY(설정)에서 분리됐다 —
/// 기록은 콘텐츠지 설정이 아니다(2026-08-10 결정, 설계 문서 §2).
class MyRecordScreen extends ConsumerWidget {
  const MyRecordScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final link = ref.watch(myConfirmedLinkProvider);
    final results = ref.watch(myPlayerResultsProvider);
    final rankings = ref.watch(myCurrentRankingsProvider);
    final snapshots = ref.watch(myRankingHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('내 기록')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: link.when(
          loading: () => const RecordSkeleton(),
          error: (_, __) => const RecordMessage('기록을 불러오지 못했습니다.'),
          data: (l) => l == null
              ? const ConnectPrompt()
              : results.when(
                  loading: () => const RecordSkeleton(),
                  error: (_, __) => const RecordMessage('기록을 불러오지 못했습니다.'),
                  data: (rows) => RecordContent(
                    results: rows,
                    rankings: rankings.value ?? const [],
                    snapshots: snapshots.value ?? const [],
                  ),
                ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Wire the route**

`app/lib/router.dart`에서 `import 'screens/rankings/rankings_screen.dart';` 줄(29번째 근처) 바로 아래에 추가:
```dart
import 'screens/rankings/my_record_screen.dart';
```

`GoRoute(path: '/rankings', builder: (_, __) => catalogAware(RankingsScreen.new))` 바로 뒤에 추가:
```dart
          GoRoute(
            path: '/rankings/me',
            builder: (_, __) => catalogAware(MyRecordScreen.new),
          ),
```

`_MainShell._untabbedPaths` 리스트(오늘 `/profile`을 추가해둔 그 리스트)에 `/rankings/me`를 추가:
```dart
  static const _untabbedPaths = [
    '/more',
    '/notifications',
    '/favorites',
    '/blocked-users',
    '/profile',
    '/rankings/me',
  ];
```

- [ ] **Step 3: Add the entry button on the ranking tab**

`app/lib/screens/rankings/rankings_screen.dart` 상단 import 블록에 추가:
```dart
import 'package:go_router/go_router.dart';
```

부서 `DropdownButtonFormField`를 감싼 `Padding`(§2에서 확인한 대로 검색창 `TextField` 바로 위) 다음에, 검색창 `Padding` 앞에 삽입:
```dart
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => context.push('/rankings/me'),
                icon: const Icon(Icons.query_stats_rounded),
                label: const Text('내 기록 보기'),
              ),
            ),
          ),
```

- [ ] **Step 4: Analyze**

Run: `cd app && flutter analyze lib/screens/rankings/my_record_screen.dart lib/router.dart lib/screens/rankings/rankings_screen.dart`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/rankings/my_record_screen.dart app/lib/router.dart app/lib/screens/rankings/rankings_screen.dart
git commit -m "feat(ranking): 내 기록 화면(/rankings/me) + 랭킹 탭 진입 버튼"
```

---

### Task 9: MY 화면에서 `MyRecordSection` 호출 제거

**Files:**
- Modify: `app/lib/screens/profile_screen.dart`

**Interfaces:**
- Consumes: 없음(제거만 함).

- [ ] **Step 1: Remove the import and call site**

`app/lib/screens/profile_screen.dart:16`의 다음 줄을 삭제:
```dart
import '../widgets/profile/my_record_widgets.dart';
```

`app/lib/screens/profile_screen.dart:404`의 다음 줄을 삭제(바로 다음 줄의 `SizedBox` 간격은 그대로 둔다 — `MyClubsSection` 앞의 여백으로 계속 쓰인다):
```dart
                const MyRecordSection(),
```

- [ ] **Step 2: Analyze the whole project**

Run: `cd app && flutter analyze`
Expected: `No issues found!` — Task 6에서 미뤄둔 `MyRecordSection` 참조 에러가 여기서 해소된다.

- [ ] **Step 3: Run the full test suite**

Run: `cd app && flutter test`
Expected: 전부 PASS, 실패 0건.

- [ ] **Step 4: Commit**

```bash
git add app/lib/screens/profile_screen.dart
git commit -m "feat(ranking): MY 화면에서 내 기록 섹션을 뗀다"
```

---

### Task 10: 선수 상세시트에 시즌 기록·추이 반영

**Files:**
- Modify: `app/lib/widgets/rankings/player_detail_sheet.dart`

**Interfaces:**
- Consumes: `playerRankingHistory()`(Task 5), `RecordContent`의 `snapshots` 파라미터(Task 6).

- [ ] **Step 1: Replace the `FutureBuilder` to fetch both results and snapshots**

`app/lib/widgets/rankings/player_detail_sheet.dart`에서 `import '../../models/player_result.dart';` 아래에 추가:
```dart
import '../../models/org_ranking_snapshot.dart';
```

기존:
```dart
              if (orgPlayerId == null)
                Text('전적을 조회할 수 없는 행입니다.', style: tt.bodyMedium)
              else
                FutureBuilder<List<PlayerResult>>(
                  future: ref
                      .read(apiProvider)
                      .playerResults(orgCode: row.orgCode, orgPlayerId: orgPlayerId),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    if (snap.hasError) {
                      return Text('전적을 불러오지 못했습니다.', style: tt.bodyMedium);
                    }
                    return RecordContent(
                      results: snap.data ?? const [],
                      rankings: [row],
                    );
                  },
                ),
```

로 교체:
```dart
              if (orgPlayerId == null)
                Text('전적을 조회할 수 없는 행입니다.', style: tt.bodyMedium)
              else
                FutureBuilder<
                    ({List<PlayerResult> results, List<OrgRankingSnapshot> snapshots})>(
                  future: _loadRecord(ref, row, orgPlayerId),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    if (snap.hasError) {
                      return Text('전적을 불러오지 못했습니다.', style: tt.bodyMedium);
                    }
                    final data = snap.data;
                    return RecordContent(
                      results: data?.results ?? const [],
                      rankings: [row],
                      snapshots: data?.snapshots ?? const [],
                    );
                  },
                ),
```

- [ ] **Step 2: Add the combined-fetch helper**

`_PlayerDetailSheet` 클래스(`class _PlayerDetailSheet extends ConsumerWidget { ... }`) 바로 뒤, 파일 끝에 top-level 함수로 추가:
```dart
Future<({List<PlayerResult> results, List<OrgRankingSnapshot> snapshots})>
    _loadRecord(WidgetRef ref, OrgRankingRow row, String orgPlayerId) async {
  final api = ref.read(apiProvider);
  final results = await api.playerResults(
    orgCode: row.orgCode,
    orgPlayerId: orgPlayerId,
  );
  final snapshots = await api.playerRankingHistory(
    orgCode: row.orgCode,
    divisionCode: row.divisionCode,
    orgPlayerId: orgPlayerId,
  );
  return (results: results, snapshots: snapshots);
}
```

- [ ] **Step 3: Analyze**

Run: `cd app && flutter analyze lib/widgets/rankings/player_detail_sheet.dart`
Expected: `No issues found!`

- [ ] **Step 4: Manual verification (no automated test — this file has none yet)**

시뮬레이터(또는 실기기)에서: 랭킹 탭 → 아무 선수나 탭 → 시트가 열리고, 전적이 있는 선수는 "이 시즌 기록" 카드 + 추이 그래프가, 전적이 없는 선수는 추이 그래프만(스냅샷이 있다면) 보이는지 확인.

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/rankings/player_detail_sheet.dart
git commit -m "feat(ranking): 선수 상세시트에 이 시즌 기록·순위 추이 반영"
```

---

### Task 11: 전체 회귀 확인

**Files:** 없음(검증만).

- [ ] **Step 1: Full analyze**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: Full test suite**

Run: `cd app && flutter test`
Expected: 전부 PASS, 실패 0건.

- [ ] **Step 3: Manual smoke test in simulator**

- `/rankings` → "내 기록 보기" 버튼 클릭 → 미연결 계정이면 유도 카드, 연결 계정이면 기록 화면(현재 순위 → 이 시즌 기록 → 추이 → 최고의 순간 → 전적)이 뜨는지
- MY 화면에 "내 기록" 섹션이 더 이상 없는지(프로필/설정만 남았는지)
- 랭킹 표에서 아무 선수나 탭 → 상세시트에 이 시즌 기록·추이가 붙는지

- [ ] **Step 4: No commit needed** — 검증 전용 태스크.
