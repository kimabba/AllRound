#!/usr/bin/env python3
"""Match-up chat 비용·캐시 로그 분석기 (JY-10, 비용절감 계획 Day 7).

`supabase/functions/chat/index.ts` 가 내보내는 구조화 로그를 파싱해
QA cache 히트율 / intent 분포 / routing(LLM 우회) 비율 / 임베딩 호출 수 등을
집계한다. 운영 비용·품질 모니터링용으로, 별도 인프라 없이 `docker logs` 또는
Supabase 로그 export 를 그대로 흘려넣어 쓴다.

로그 형식
---------
chat/index.ts 는 `console.log('<marker>', JSON.stringify({event, ...}))` 형태로
한 줄에 하나의 이벤트를 찍는다. 플랫폼이 타임스탬프 등 prefix 를 붙여도
줄 안에서 마커와 그 뒤의 JSON 오브젝트만 찾아 파싱한다.

  marker         events
  ------         ------
  chat_intent    classify, refuse_unregistered_sport, knn_rpc_error, knn_exception
  chat_cache     hit, miss, skip_history, skip_sport_filter, skip_no_embedding,
                 insert, insert_skipped_duplicate, insert_failed
  chat_route     tournament_search_routed, tournament_search_empty,
                 tournament_search_rpc_error

사용법
------
  cat chat.log | python3 scripts/analyze_chat_cost.py
  python3 scripts/analyze_chat_cost.py chat.log other.log
  python3 scripts/analyze_chat_cost.py --json chat.log

종료 코드: 파싱 자체는 항상 0. 입력에서 유효 이벤트를 하나도 못 찾으면 2.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from dataclasses import dataclass, field
from typing import Iterable, Iterator, Optional

MARKERS = ("chat_intent", "chat_cache", "chat_route")


@dataclass
class Stats:
    """파싱된 이벤트의 누적 집계."""

    # chat_intent
    classify_total: int = 0
    intent_counts: Counter = field(default_factory=Counter)
    method_counts: Counter = field(default_factory=Counter)
    routable: int = 0
    has_embedding: int = 0
    refuse_unregistered_sport: int = 0
    knn_errors: int = 0

    # chat_cache
    cache_hit: int = 0
    cache_miss: int = 0
    cache_skip: Counter = field(default_factory=Counter)
    cache_insert: int = 0
    cache_insert_dupe: int = 0
    cache_insert_failed: int = 0

    # chat_route
    routed: int = 0
    routed_result_total: int = 0
    routed_empty: int = 0
    route_rpc_error: int = 0

    # 메타
    events_parsed: int = 0
    lines_seen: int = 0
    parse_errors: int = 0


def extract_event(line: str) -> Optional[tuple[str, dict]]:
    """한 줄에서 (marker, payload) 추출. 마커·JSON 못 찾으면 None.

    가장 먼저 등장하는 마커를 채택하고, 그 뒤 첫 '{' 부터 괄호 균형이 맞는
    지점까지를 JSON 으로 파싱한다 (줄 뒤에 trailing 텍스트가 붙어도 안전).
    """
    marker_pos = -1
    marker_name = ""
    for m in MARKERS:
        idx = line.find(m)
        if idx != -1 and (marker_pos == -1 or idx < marker_pos):
            marker_pos = idx
            marker_name = m
    if marker_pos == -1:
        return None

    brace = line.find("{", marker_pos)
    if brace == -1:
        return None

    depth = 0
    in_str = False
    escaped = False
    end = -1
    for i in range(brace, len(line)):
        ch = line[i]
        if in_str:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_str = False
            continue
        if ch == '"':
            in_str = True
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                end = i + 1
                break
    if end == -1:
        return None

    try:
        payload = json.loads(line[brace:end])
    except json.JSONDecodeError:
        return None
    if not isinstance(payload, dict):
        return None
    return marker_name, payload


def consume(stats: Stats, marker: str, payload: dict) -> None:
    """단일 이벤트를 Stats 에 반영."""
    event = payload.get("event")
    stats.events_parsed += 1

    if marker == "chat_intent":
        if event == "classify":
            stats.classify_total += 1
            intent = payload.get("intent")
            if isinstance(intent, str):
                stats.intent_counts[intent] += 1
            method = payload.get("method")
            if isinstance(method, str):
                stats.method_counts[method] += 1
            if payload.get("routable") is True:
                stats.routable += 1
            if payload.get("has_embedding") is True:
                stats.has_embedding += 1
        elif event == "refuse_unregistered_sport":
            stats.refuse_unregistered_sport += 1
        elif event in ("knn_rpc_error", "knn_exception"):
            stats.knn_errors += 1

    elif marker == "chat_cache":
        if event == "hit":
            stats.cache_hit += 1
        elif event == "miss":
            stats.cache_miss += 1
        elif event in ("skip_history", "skip_sport_filter", "skip_no_embedding"):
            stats.cache_skip[event] += 1
        elif event == "insert":
            stats.cache_insert += 1
        elif event == "insert_skipped_duplicate":
            stats.cache_insert_dupe += 1
        elif event == "insert_failed":
            stats.cache_insert_failed += 1

    elif marker == "chat_route":
        if event == "tournament_search_routed":
            stats.routed += 1
            rc = payload.get("result_count")
            if isinstance(rc, int):
                stats.routed_result_total += rc
        elif event == "tournament_search_empty":
            stats.routed_empty += 1
        elif event == "tournament_search_rpc_error":
            stats.route_rpc_error += 1


def analyze(lines: Iterable[str]) -> Stats:
    stats = Stats()
    for line in lines:
        stats.lines_seen += 1
        got = extract_event(line)
        if got is None:
            continue
        marker, payload = got
        consume(stats, marker, payload)
    return stats


def _pct(part: int, whole: int) -> Optional[float]:
    if whole <= 0:
        return None
    return round(100.0 * part / whole, 1)


def to_report(stats: Stats) -> dict:
    """집계 + 파생 지표를 dict 로. JSON 출력과 텍스트 출력이 공유."""
    looked_up = stats.cache_hit + stats.cache_miss
    # LLM 호출을 확정적으로 우회한 요청 (하한선): cache hit + slot routing + 미등록종목 거부.
    # free_chat 등 RAG 0건 거부도 LLM 을 안 부르지만 로그로 단정 불가 → 하한선에서 제외.
    llm_bypassed_lower = stats.cache_hit + stats.routed + stats.refuse_unregistered_sport
    return {
        "totals": {
            "lines_seen": stats.lines_seen,
            "events_parsed": stats.events_parsed,
            "classified_requests": stats.classify_total,
        },
        "cache": {
            "hit": stats.cache_hit,
            "miss": stats.cache_miss,
            "looked_up": looked_up,
            "hit_rate_pct": _pct(stats.cache_hit, looked_up),
            "skip": dict(stats.cache_skip),
            "insert": stats.cache_insert,
            "insert_skipped_duplicate": stats.cache_insert_dupe,
            "insert_failed": stats.cache_insert_failed,
        },
        "intent": {
            "distribution": dict(stats.intent_counts.most_common()),
            "method": dict(stats.method_counts.most_common()),
            "routable": stats.routable,
            "routable_rate_pct": _pct(stats.routable, stats.classify_total),
            "knn_errors": stats.knn_errors,
        },
        "routing": {
            "routed": stats.routed,
            "routed_result_total": stats.routed_result_total,
            "routed_empty_fallback": stats.routed_empty,
            "rpc_error": stats.route_rpc_error,
        },
        "derived": {
            # 임베딩(text-embedding)은 분류된 요청 대부분에서 호출됨 — 비용 proxy.
            "embedding_calls_est": stats.has_embedding,
            "llm_calls_avoided_lower_bound": llm_bypassed_lower,
            "refuse_unregistered_sport": stats.refuse_unregistered_sport,
        },
    }


def _fmt_pct(v: Optional[float]) -> str:
    return f"{v}%" if v is not None else "n/a"


def render_text(report: dict) -> str:
    t = report["totals"]
    c = report["cache"]
    i = report["intent"]
    r = report["routing"]
    d = report["derived"]
    out: list[str] = []
    out.append("== Match-up chat 비용·캐시 로그 분석 ==")
    out.append(
        f"라인 {t['lines_seen']} / 이벤트 {t['events_parsed']} / 분류요청 "
        f"{t['classified_requests']}"
    )
    out.append("")
    out.append("[QA cache]")
    out.append(
        f"  hit {c['hit']} · miss {c['miss']} · lookup {c['looked_up']} "
        f"→ hit rate {_fmt_pct(c['hit_rate_pct'])} (목표 40%+)"
    )
    if c["skip"]:
        skips = ", ".join(f"{k}={v}" for k, v in sorted(c["skip"].items()))
        out.append(f"  skip: {skips}")
    out.append(
        f"  insert {c['insert']} · dup {c['insert_skipped_duplicate']} · "
        f"failed {c['insert_failed']}"
    )
    out.append("")
    out.append("[Intent]")
    if i["distribution"]:
        for name, cnt in i["distribution"].items():
            out.append(f"  {name:18s} {cnt}")
    if i["method"]:
        methods = ", ".join(f"{k}={v}" for k, v in i["method"].items())
        out.append(f"  method: {methods}")
    out.append(
        f"  routable {i['routable']} → {_fmt_pct(i['routable_rate_pct'])}"
        + (f" · knn_errors {i['knn_errors']}" if i["knn_errors"] else "")
    )
    out.append("")
    out.append("[Routing — LLM 우회]")
    out.append(
        f"  routed {r['routed']} (결과 {r['routed_result_total']}건) · "
        f"empty→fallback {r['routed_empty_fallback']} · rpc_error {r['rpc_error']}"
    )
    out.append("")
    out.append("[파생 — 비용 proxy]")
    out.append(f"  임베딩 호출(추정): {d['embedding_calls_est']}")
    out.append(f"  LLM 호출 회피(하한): {d['llm_calls_avoided_lower_bound']}")
    out.append(f"  미등록종목 거부: {d['refuse_unregistered_sport']}")
    return "\n".join(out)


def read_inputs(paths: list[str]) -> Iterator[str]:
    if not paths:
        yield from sys.stdin
        return
    for p in paths:
        with open(p, "r", encoding="utf-8", errors="replace") as fh:
            yield from fh


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Match-up chat 비용·캐시 로그 분석기")
    parser.add_argument("paths", nargs="*", help="로그 파일 (없으면 stdin)")
    parser.add_argument("--json", action="store_true", help="JSON 으로 출력")
    args = parser.parse_args(argv)

    stats = analyze(read_inputs(args.paths))
    report = to_report(stats)

    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print(render_text(report))

    return 0 if stats.events_parsed > 0 else 2


if __name__ == "__main__":
    raise SystemExit(main())
