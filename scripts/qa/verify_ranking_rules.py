#!/usr/bin/env python3
"""광주 랭킹 포인트 rule_config 검증기.

배점표는 money-path 다. 규정 원문과 어긋나면 여기서 즉시 실패한다.
- 구조 검증: 모든 그레이드·라운드가 채워졌고 값이 음수 아님, 상위 라운드 >= 하위 라운드.
- 스팟 검증: 규정 원문(docs/research/tennis-ranking-point-rules.md §3.1)의 대표 셀과 대조.

의존성 없음. 실행: python3 scripts/qa/verify_ranking_rules.py
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RULES = ROOT / "supabase" / "seed-data" / "ranking-rules"

# 규정 원문 대표 셀 (배점표가 바뀌면 이 기대값과 어긋나 실패한다)
GJ_2026_SPOT = {
    "winner": {
        ("A", "champion"): 1000, ("A", "r32"): 30, ("A", "entry"): 5,
        ("1", "runner_up"): 560, ("3", "champion"): 500, ("3", "r32"): 15,
    },
    "non_winner": {
        ("A", "champion"): 800, ("A", "r64"): 12, ("A", "entry"): 3,
        ("2", "quarter"): 91, ("3", "champion"): 360, ("3", "r64"): 6,
    },
}
# 우승자표에는 r64 가 없고(2026 개정으로 삭제), 비우승자표에만 있다.
GJ_WINNER_ROUNDS = ["champion", "runner_up", "semi", "quarter", "r16", "r32", "entry"]
GJ_NON_WINNER_ROUNDS = GJ_WINNER_ROUNDS[:-1] + ["r64", "entry"]
# 값이 큰 순서(참가점수 entry 는 예외 — 별도 취급)
DESC = ["champion", "runner_up", "semi", "quarter", "r16", "r32", "r64"]


def fail(msg):
    print(f"  ✗ {msg}")
    fail.count += 1
fail.count = 0


def check_table(name, table, rounds):
    by_grade = table["by_grade"]
    for grade, row in by_grade.items():
        keys = [r for r in DESC if r in row]
        for r in rounds:
            if r not in row:
                fail(f"[{name}/{grade}] 라운드 '{r}' 누락")
            elif not isinstance(row[r], int) or row[r] < 0:
                fail(f"[{name}/{grade}] '{r}' 값이 음수/비정수: {row[r]!r}")
        # 단조 감소 (참가점수 entry 제외): 우승 >= 준우승 >= 4강 …
        present = [r for r in DESC if r in row]
        for a, b in zip(present, present[1:]):
            if row[a] < row[b]:
                fail(f"[{name}/{grade}] {a}({row[a]}) < {b}({row[b]}) — 상위 라운드가 더 낮음")


def main():
    path = RULES / "gj-2026.json"
    if not path.exists():
        print(f"파일 없음: {path}")
        return 1
    cfg = json.loads(path.read_text(encoding="utf-8"))

    print("광주 2026 rule_config 검증")
    pt = cfg["point_tables"]
    check_table("winner", pt["winner"], GJ_WINNER_ROUNDS)
    check_table("non_winner", pt["non_winner"], GJ_NON_WINNER_ROUNDS)

    # 스팟 검증 — 규정 원문 대표값
    for tkey, cells in GJ_2026_SPOT.items():
        by_grade = pt[tkey]["by_grade"]
        for (grade, rnd), expect in cells.items():
            got = by_grade.get(grade, {}).get(rnd)
            if got != expect:
                fail(f"[{tkey}/{grade}/{rnd}] 규정값 {expect} 인데 {got}")

    # 우승자표에 r64 가 있으면 2026 개정 반영 오류 (구본엔 있었음)
    for grade, row in pt["winner"]["by_grade"].items():
        if "r64" in row:
            fail(f"[winner/{grade}] r64 는 2026 현행에서 삭제됨 — 구본 값 혼입 의심")

    # 집계 모순이 플래그되어 있는지 (해소 전까지 계산 금지 신호)
    agg = cfg["aggregation"]
    if agg.get("ranking_best_n") == agg.get("award_best_n"):
        fail("aggregation: 베스트25/15 모순이 사라짐 — 협회 확인 없이 값을 통일하지 말 것")
    if "conflict" not in agg:
        fail("aggregation.conflict 플래그 누락 — 미해소 모순 표시가 있어야 함")

    if fail.count:
        print(f"\n실패 {fail.count}건")
        return 1
    print("  ✓ 구조·스팟·개정반영·모순플래그 전부 통과")
    return 0


if __name__ == "__main__":
    sys.exit(main())
