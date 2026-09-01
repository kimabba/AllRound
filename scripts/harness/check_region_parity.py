#!/usr/bin/env python3
"""지역 정본(public.regions) ↔ 클라이언트 폴백 스냅샷의 일치를 **실제 DB 로** 강제한다.

왜 DB 대조인가:
    P7 에서 지역 목록·라벨 정본을 Dart 하드코딩(regionCodes/regionLabels)에서 DB
    regions 로 옮기며 check_enums.py 의 지역 3층 비교(Dart↔TS↔seed 정규식 파싱)를
    없앴다. 협회(JY-135, #330)와 같은 상황 — 검사를 그냥 없애면 앱 폴백 상수가
    DB 와 어긋나도 아무도 못 잡는 공백이 생긴다.

왜 Dart 소스를 정규식으로 읽지 않는가:
    check_org_parity.py 와 같은 결론(#322, codex 반복 지적): 소스 정규식 파싱은
    주석·이스케이프·공백 변형의 사각지대가 끝이 없다. 그래서 **스냅샷 다리**를 둔다:
      DB ──(이 스크립트)──▶ app/test/fixtures/region_fallback.json ◀──(Flutter 테스트)── Dart 폴백
    Flutter 테스트(app/test/grade_labels_test.dart)가 RegionCatalog 폴백을 이 JSON
    스냅샷과 비교한다. 이 스크립트는 같은 스냅샷을 DB 와 비교한다. 둘 중 하나만
    어긋나도 한쪽 잡이 반드시 빨간불이 된다.

비교 순서는 code 알파벳순이다:
    regions 엔 sort_order 컬럼이 없고, 표시 순서(지도상 수도권→…→제주)는 앱
    RegionCatalog 폴백이 정한다. 그래서 순서 비교는 의미가 없고, 양쪽을 code 순으로
    정렬해 (code, label, isActive) 값만 대조한다. Flutter 쪽 테스트도 같은 규칙이다.

전제: `supabase db reset`(또는 CI 의 `supabase start`)로 마이그레이션이 이미 적용됐다.
DB 접속은 $DATABASE_URL, 없으면 로컬 기본값.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SNAPSHOT = ROOT / "app/test/fixtures/region_fallback.json"

DEFAULT_DB_URL = "postgresql://postgres:postgres@127.0.0.1:54322/postgres"

_SCHEMA = {"code": str, "label": str, "isActive": bool}


def _validate_entries(data, source: str) -> None:
    """스키마·타입을 강제한다. `1 == True` 라서 `isActive: 1` 이 DB 의 `true` 와 조용히
    같다고 판정되는 구멍을 막는다(check_org_parity.py 와 동일).
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


def read_regions() -> list[dict]:
    """DB 에서 (code, display_name_ko, is_active) 를 code 순으로 읽는다.

    JSON 으로 받는 이유는 check_org_parity.py 와 같다: 라벨에 가운뎃점 등 특수문자가
    있어(예: '부산·울산·경남') TSV 는 구분자 주입 위험이 있다. json_agg 는 이스케이프한다.
    """
    db_url = os.environ.get("DATABASE_URL", DEFAULT_DB_URL)
    query = (
        "select coalesce(json_agg(json_build_object("
        "'code', code, "
        "'label', display_name_ko, "
        "'isActive', is_active) "
        "order by code), '[]') from public.regions"
    )
    try:
        out = subprocess.run(
            ["psql", db_url, "-tAc", query],
            capture_output=True, text=True, check=True,
        ).stdout
    except FileNotFoundError:
        raise AssertionError("psql 이 PATH 에 없다 — DB 대조를 실행할 수 없다")
    except subprocess.CalledProcessError as exc:
        raise AssertionError(f"regions 조회 실패: {exc.stderr.strip()}")

    try:
        data = json.loads(out)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"regions JSON 파싱 실패: {exc} — 원문 {out[:200]!r}")

    if not data:
        raise AssertionError("public.regions 가 비어 있다 — 마이그레이션이 적용됐는지 확인하라")
    _validate_entries(data, "DB public.regions")
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
    return [(e["code"], e["label"], e["isActive"]) for e in entries]


def main() -> int:
    db_rows = as_rows(read_regions())
    snapshot_rows = as_rows(read_snapshot())

    if db_rows != snapshot_rows:
        lines = [
            f"DB public.regions 항목 수: {len(db_rows)}, "
            f"스냅샷 항목 수: {len(snapshot_rows)} "
            f"({SNAPSHOT.relative_to(ROOT)})",
        ]
        for i, (db_row, snap_row) in enumerate(zip(db_rows, snapshot_rows)):
            if db_row != snap_row:
                lines.append(f"  [{i}] DB={db_row}\n      snapshot={snap_row}")
        if len(db_rows) != len(snapshot_rows):
            shorter = min(len(db_rows), len(snapshot_rows))
            tail_name, tail = (
                ("DB", db_rows[shorter:])
                if len(db_rows) > len(snapshot_rows)
                else ("snapshot", snapshot_rows[shorter:])
            )
            lines.append(f"  {tail_name} 에만 있는 꼬리: {tail}")
        lines.append(
            "  ※ 폴백(Dart)이 스냅샷과 일치하는지는 `flutter test` 의 "
            "RegionCatalog 스냅샷 테스트가 따로 검증한다."
        )
        raise AssertionError("\n".join(lines))

    print(f"✓ region catalog ({len(db_rows)}개 일치, 순서: code)")
    for code, label, active in db_rows:
        print(f"  {code}: {label!r} / active={active}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"❌ region parity failed:\n{exc}", file=sys.stderr)
        raise SystemExit(1)
