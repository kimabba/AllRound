#!/usr/bin/env python3
"""Check enum/list consistency across Dart, Deno TypeScript, and SQL.

This script intentionally checks only stable cross-layer domain values.
It should fail fast when a value is added in one layer but not the others.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

DART_ENUMS = ROOT / "app/lib/utils/grade_labels.dart"
TS_ENUMS = ROOT / "supabase/functions/_shared/enums.ts"
SQL_USERS = ROOT / "supabase/migrations/002_init_users_sports.sql"
SQL_MIGRATIONS = ROOT / "supabase/migrations"
SQL_ORGS = ROOT / "supabase/migrations/009_regions_and_multi_org.sql"


def read(path: Path) -> str:
    if not path.exists():
        raise AssertionError(f"missing required file: {path.relative_to(ROOT)}")
    return path.read_text(encoding="utf-8")



def quoted_values(text: str) -> list[str]:
    return re.findall(r"'([^']+)'", text)


# 이 파일 안에서는 호출부가 없지만 check_grades_parity.py 가 `import check_enums` 로
# 재사용한다(_kFallbackTennisGrades/_kFallbackFutsalGrades 추출). 지우면 CI Database
# 잡이 AttributeError 로 죽는다 — P7 에서 지역 검사를 걷어내며 한 번 겪었다.
def dart_const_list(text: str, name: str) -> list[str]:
    pattern = rf"const\s+{re.escape(name)}\s*=\s*(?:<String>)?\s*\[(.*?)\];"
    match = re.search(pattern, text, re.S)
    if not match:
        raise AssertionError(f"Dart const list not found: {name}")
    return quoted_values(match.group(1))


def dart_enum(text: str, name: str) -> list[str]:
    match = re.search(rf"enum\s+{re.escape(name)}\s*\{{(.*?)\}}", text, re.S)
    if not match:
        raise AssertionError(f"Dart enum not found: {name}")
    return [part.strip() for part in match.group(1).split(",") if part.strip()]


def ts_const_array(text: str, name: str) -> list[str]:
    pattern = rf"export\s+const\s+{re.escape(name)}\s*=\s*\[(.*?)\]\s+as\s+const"
    match = re.search(pattern, text, re.S)
    if not match:
        raise AssertionError(f"TypeScript const array not found: {name}")
    return quoted_values(match.group(1))


def sql_enum(text: str, name: str) -> list[str]:
    pattern = rf"create\s+type\s+(?:public\.)?\"?{re.escape(name)}\"?\s+as\s+enum\s*\((.*?)\);"
    match = re.search(pattern, text, re.I | re.S)
    if not match:
        raise AssertionError(f"SQL enum not found: {name}")
    return quoted_values(match.group(1))


def sql_enum_after_history(text: str, name: str) -> list[str]:
    """CREATE TYPE 이후의 ALTER TYPE ... ADD/RENAME VALUE 까지 반영한 최종 enum 값.

    CREATE 만 읽으면 이후 마이그레이션이 값을 추가·개명해도 드리프트를 놓친다.
    ADD VALUE BEFORE/AFTER 의 삽입 위치는 반영하지 않고 뒤에 붙인다(순서 비교 한계).
    """
    values = sql_enum(text, name)
    quoted_name = rf"alter\s+type\s+(?:public\.)?\"?{re.escape(name)}\"?\s+"
    for path in sorted(SQL_MIGRATIONS.glob("*.sql")):
        migration = read(path)
        added = re.finditer(
            quoted_name + r"add\s+value\s+(?:if\s+not\s+exists\s+)?'([^']+)'",
            migration,
            re.I,
        )
        for match in added:
            if match.group(1) not in values:
                values.append(match.group(1))
        renamed = re.finditer(
            quoted_name + r"rename\s+value\s+'([^']+)'\s+to\s+'([^']+)'",
            migration,
            re.I,
        )
        for match in renamed:
            old, new = match.group(1), match.group(2)
            values = [new if value == old else value for value in values]
    return values


def dart_const_map(text: str, name: str) -> list[str]:
    pattern = rf"const\s+{re.escape(name)}\s*=\s*<String,\s*String>\{{(.*?)\}};"
    match = re.search(pattern, text, re.S)
    if not match:
        raise AssertionError(f"Dart const map not found: {name}")
    entries = re.findall(r"'([^']+)'\s*:\s*'([^']+)'", match.group(1))
    if not entries:
        raise AssertionError(f"Dart const map is empty: {name}")
    return [f"{key}={value}" for key, value in entries]


def dart_sport_label_map(text: str) -> list[str]:
    """`const sportLabels = <Sport, String>{ Sport.tennis: '테니스', ... }` — 키는 enum 멤버."""
    match = re.search(r"const\s+sportLabels\s*=\s*<Sport,\s*String>\{(.*?)\};", text, re.S)
    if not match:
        raise AssertionError("Dart const map not found: sportLabels")
    entries = re.findall(r"Sport\.([A-Za-z0-9_]+)\s*:\s*'([^']+)'", match.group(1))
    if not entries:
        raise AssertionError("Dart const map is empty: sportLabels")
    return [f"{key}={value}" for key, value in entries]


def ts_record(text: str, name: str) -> list[str]:
    pattern = rf"export\s+const\s+{re.escape(name)}\s*:\s*Record<[^>]+>\s*=\s*\{{(.*?)\}};"
    match = re.search(pattern, text, re.S)
    if not match:
        raise AssertionError(f"TypeScript record not found: {name}")
    entries = re.findall(r"'?([A-Za-z0-9_]+)'?\s*:\s*'([^']+)'", match.group(1))
    if not entries:
        raise AssertionError(f"TypeScript record is empty: {name}")
    return [f"{key}={value}" for key, value in entries]


def sql_entry_fee_units(text: str) -> list[str]:
    match = re.search(r"entry_fee_unit\s+text\s+not\s+null\s+default\s+'[^']+'\s+check\s*\(\s*entry_fee_unit\s+in\s*\((.*?)\)\s*\)", text, re.I | re.S)
    if not match:
        raise AssertionError("SQL entry_fee_unit check not found")
    return quoted_values(match.group(1))


def assert_same(name: str, *values: tuple[str, list[str]]) -> None:
    baseline_label, baseline = values[0]
    failures: list[str] = []
    for label, current in values[1:]:
        if current != baseline:
            failures.append(
                f"{name}: {label} differs from {baseline_label}\n"
                f"  {baseline_label}: {baseline}\n"
                f"  {label}: {current}"
            )
    if failures:
        raise AssertionError("\n".join(failures))
    print(f"✓ {name}: {baseline}")


def main() -> int:
    dart = read(DART_ENUMS)
    ts = read(TS_ENUMS)
    sql_users = read(SQL_USERS)
    sql_orgs = read(SQL_ORGS)

    assert_same(
        "sports",
        ("Dart Sport", dart_enum(dart, "Sport")),
        ("TypeScript SPORTS", ts_const_array(ts, "SPORTS")),
        ("SQL sport", sql_enum_after_history(sql_users, "sport")),
    )
    # 등급(grades)의 정본↔폴백 대조는 check_grades_parity.py 가 **실제 DB** 로 한다.
    # 마이그레이션을 정규식 파싱하면 유효 SQL 문법으로 grades 쓰기를 숨길 수 있어
    # fail-open 우회가 반복됐다(codex 5~11차). 파싱을 버리고 적용된 DB 를 직접 읽는다(JY-321).
    assert_same(
        "sport labels",
        ("Dart sportLabels", dart_sport_label_map(dart)),
        ("TypeScript SPORT_LABELS", ts_record(ts, "SPORT_LABELS")),
    )
    # 협회(tennis_orgs)의 정본은 DB 다(JY-135). Dart 는 폴백만 갖고 SQL enum 은
    # 20260711002939 에서 이미 삭제됐다 — 이 검사는 죽은 타입 텍스트를 파싱하고
    # 있었다. 등급이 JY-321 에서 실제 DB 조회로 옮겨간 것과 같은 방향이다.
    # 후속: 폴백↔DB 대조를 check_grades_parity.py 방식으로 추가.
    #
    # 지역(regions)의 정본도 DB 다(P7). Dart 하드코딩(regionCodes)은 RegionCatalog
    # 폴백으로 옮겨갔고, 폴백↔DB 대조는 check_region_parity.py 가 실제 DB 로 한다
    # (협회 #330 과 같은 스냅샷 다리). TS 쪽 검증(submit/search)도 DB 위임으로
    # 전환됐다(_shared/regions.ts, P7 마지막 조각). 남은 REGION_CODES 는 intent
    # 별칭·라벨 표시용 정적 사본이라 이 검사 대상이 아니다.
    assert_same(
        "entry fee units",
        ("TypeScript ENTRY_FEE_UNITS", ts_const_array(ts, "ENTRY_FEE_UNITS")),
        ("SQL entry_fee_unit check", sql_entry_fee_units(sql_orgs)),
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"❌ enum consistency failed:\n{exc}", file=sys.stderr)
        raise SystemExit(1)
