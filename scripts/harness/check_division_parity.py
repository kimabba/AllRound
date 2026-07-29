#!/usr/bin/env python3
"""부서 정본(public.tennis_divisions) ↔ 클라이언트 폴백 스냅샷의 일치를 **실제 DB 로** 강제한다.

check_org_parity.py 와 같은 **스냅샷 다리** 구조다:
    DB ──(이 스크립트)──▶ app/test/fixtures/division_fallback.json ◀──(Flutter 테스트)── Dart 폴백

왜 부서에도 필요한가:
    협회(tennis_orgs)·등급(grades)에는 이 다리가 있었지만 부서에는 없었다. 랭킹 등급과
    대회 종목을 가르는 is_ranking_grade 가 생기면서 그 공백이 실제 위험이 됐다 — 분류를
    한 칸 잘못 넣거나 마이그레이션에서 코드 하나를 빠뜨려도 잡히지 않는다(codex 지적):
      · 마이그레이션에서 kato_couple / kato_mixed / kta_mixed 중 일부 누락
      · 폴백에서 코드 삭제 → "모든 division 왕복" 테스트는 목록 자체를 순회하므로
        삭제된 코드가 검사 대상에서 함께 사라진다(조용히 약해짐)

무엇을 비교하나:
    (code, org, label, isRankingGrade, isActive) 5개. synonyms·score_min/max·gender 는
    Dart 폴백이 들고 있지 않거나(전자) 표시에 쓰이지 않아(후자) 대조 대상이 아니다.

    **비활성 부서도 포함한다.** 폴백은 목록(all)이 아니라 라벨 해석까지 책임지므로
    is_active=false 인 행도 들고 있어야 한다 — 과거 대회 상세에 'ktfs_open' 같은
    코드 원문이 뜨면 안 된다.

전제: `supabase db reset`(또는 CI 의 `supabase start`)로 마이그레이션이 이미 적용됐다.
DB 접속은 $DATABASE_URL, 없으면 로컬 기본값.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SNAPSHOT = ROOT / "app/test/fixtures/division_fallback.json"

DEFAULT_DB_URL = "postgresql://postgres:postgres@127.0.0.1:54322/postgres"

_SCHEMA = {
    "code": str,
    "org": str,
    "label": str,
    "isRankingGrade": bool,
    "isActive": bool,
}


def _validate_entries(data, source: str) -> None:
    """스키마·타입을 강제한다. `1 == True` 라서 불리언 칸에 숫자가 들어와도 조용히
    같다고 판정되는 구멍을 막는다 — `isinstance(1, bool)` 은 False 다.
    """
    if not isinstance(data, list):
        raise AssertionError(f"{source}: 최상위가 리스트가 아니다 (type={type(data).__name__})")
    for i, entry in enumerate(data):
        if not isinstance(entry, dict):
            raise AssertionError(f"{source}[{i}]: 객체가 아니다 (type={type(entry).__name__})")
        extra = set(entry) - set(_SCHEMA)
        missing = set(_SCHEMA) - set(entry)
        if extra or missing:
            raise AssertionError(
                f"{source}[{i}]: 키가 어긋난다 — 누락 {sorted(missing)}, 여분 {sorted(extra)}"
            )
        for key, expected in _SCHEMA.items():
            value = entry[key]
            if not isinstance(value, expected):
                raise AssertionError(
                    f"{source}[{i}].{key}: {expected.__name__} 이어야 하는데 "
                    f"{value!r} ({type(value).__name__})"
                )


def read_divisions() -> list[dict]:
    """DB 에서 부서를 **org 표시순 → code 순**으로 읽는다.

    앱 DivisionCatalog._sortByOrgPriority 가 OrgCatalog 순서(tennis_orgs.sort_order)로
    그룹핑하고 그룹 안에서는 쿼리 순서(code)를 보존하므로, 여기서도 같은 순서를 만든다.
    org 가 tennis_orgs 에 없으면 뒤로 민다(앱의 unknown 버킷과 같은 취급).

    JSON 으로 받는 이유는 check_org_parity.py 와 같다: 라벨에 가운뎃점·괄호가 들어 있어
    TSV 는 컬럼 경계가 깨질 위험이 있다. json_agg 는 특수문자를 이스케이프한다.
    """
    db_url = os.environ.get("DATABASE_URL", DEFAULT_DB_URL)
    query = (
        "select coalesce(json_agg(json_build_object("
        "'code', d.code, "
        "'org', d.org_code, "
        "'label', d.label_ko, "
        "'isRankingGrade', d.is_ranking_grade, "
        "'isActive', d.is_active) "
        "order by coalesce(o.sort_order, 2147483647), d.org_code, d.code), '[]') "
        "from public.tennis_divisions d "
        "left join public.tennis_orgs o on o.code = d.org_code"
    )
    try:
        out = subprocess.run(
            ["psql", db_url, "-tAc", query],
            capture_output=True, text=True, check=True,
        ).stdout
    except FileNotFoundError:
        raise AssertionError("psql 이 PATH 에 없다 — DB 대조를 실행할 수 없다")
    except subprocess.CalledProcessError as exc:
        raise AssertionError(f"tennis_divisions 조회 실패: {exc.stderr.strip()}")

    try:
        data = json.loads(out)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"tennis_divisions JSON 파싱 실패: {exc} — 원문 {out[:200]!r}")

    if not data:
        raise AssertionError(
            "public.tennis_divisions 가 비어 있다 — 마이그레이션이 적용됐는지 확인하라"
        )
    _validate_entries(data, "DB public.tennis_divisions")
    return data


def read_snapshot() -> list[dict]:
    if not SNAPSHOT.exists():
        raise AssertionError(f"missing required file: {SNAPSHOT.relative_to(ROOT)}")
    try:
        data = json.loads(SNAPSHOT.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise AssertionError(f"{SNAPSHOT.relative_to(ROOT)} JSON 파싱 실패: {exc}")
    if not data:
        raise AssertionError(f"{SNAPSHOT.relative_to(ROOT)} 가 비어 있다")
    _validate_entries(data, str(SNAPSHOT.relative_to(ROOT)))
    return data


def as_rows(entries: list[dict]) -> list[tuple]:
    return [
        (e["code"], e["org"], e["label"], e["isRankingGrade"], e["isActive"])
        for e in entries
    ]


def main() -> int:
    db_rows = as_rows(read_divisions())
    snapshot_rows = as_rows(read_snapshot())

    if db_rows != snapshot_rows:
        db_by_code = {r[0]: r for r in db_rows}
        snap_by_code = {r[0]: r for r in snapshot_rows}
        lines = [
            f"DB public.tennis_divisions 항목 수: {len(db_rows)}, "
            f"스냅샷 항목 수: {len(snapshot_rows)} "
            f"({SNAPSHOT.relative_to(ROOT)})",
        ]
        for code in sorted(set(db_by_code) - set(snap_by_code)):
            lines.append(f"  DB 에만 있음: {db_by_code[code]}")
        for code in sorted(set(snap_by_code) - set(db_by_code)):
            lines.append(f"  스냅샷에만 있음: {snap_by_code[code]}")
        for code in sorted(set(db_by_code) & set(snap_by_code)):
            if db_by_code[code] != snap_by_code[code]:
                lines.append(
                    f"  값 불일치 {code}:\n"
                    f"      DB={db_by_code[code]}\n"
                    f"      snapshot={snap_by_code[code]}"
                )
        if set(db_by_code) == set(snap_by_code) and len(lines) == 1:
            lines.append("  코드 집합·값은 같은데 **순서**가 다르다 (org sort_order → code)")
        lines.append(
            "  ※ 폴백(Dart)이 스냅샷과 일치하는지는 `flutter test` 의 "
            "DivisionCatalog 스냅샷 테스트가 따로 검증한다."
        )
        raise AssertionError("\n".join(lines))

    ranking = sum(1 for r in db_rows if r[3])
    active = sum(1 for r in db_rows if r[4])
    print(
        f"✓ tennis division catalog ({len(db_rows)}개 일치 — "
        f"랭킹 등급 {ranking} / 종목 전용 {len(db_rows) - ranking} / "
        f"활성 {active} / 비활성 {len(db_rows) - active})"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"❌ division parity failed:\n{exc}", file=sys.stderr)
        raise SystemExit(1)
