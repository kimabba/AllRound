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
SQL_SEED = ROOT / "supabase/seed.sql"


def read(path: Path) -> str:
    if not path.exists():
        raise AssertionError(f"missing required file: {path.relative_to(ROOT)}")
    return path.read_text(encoding="utf-8")


def quoted_values(text: str) -> list[str]:
    return re.findall(r"'([^']+)'", text)


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


def sql_grade_check(text: str, sport: str) -> list[str]:
    # 마이그레이션 history 를 후순위 ALTER 가 덮어쓸 수 있으므로 가장 마지막 매치를 사용.
    # 예: 002 에서 정의 → 010 에서 ALTER 로 enum 교체된 경우, 010 의 정의가 운영 schema.
    pattern = rf"sport\s*=\s*'{re.escape(sport)}'\s+and\s+grade\s+in\s*\((.*?)\)"
    matches = re.findall(pattern, text, re.I | re.S)
    if not matches:
        raise AssertionError(f"SQL grade check not found for sport: {sport}")
    return quoted_values(matches[-1])


def sql_entry_fee_units(text: str) -> list[str]:
    match = re.search(r"entry_fee_unit\s+text\s+not\s+null\s+default\s+'[^']+'\s+check\s*\(\s*entry_fee_unit\s+in\s*\((.*?)\)\s*\)", text, re.I | re.S)
    if not match:
        raise AssertionError("SQL entry_fee_unit check not found")
    return quoted_values(match.group(1))


def user_sports_grade_constraint_history() -> str:
    sql_parts: list[str] = [read(SQL_USERS)]
    for path in sorted(SQL_MIGRATIONS.glob("*.sql")):
        if path == SQL_USERS:
            continue
        text = read(path)
        matches = re.finditer(
            r"alter\s+table[^;]+?add\s+constraint\s+user_sports_grade_check\s+check\s*\((.*?)\)\s*;",
            text,
            re.I | re.S,
        )
        sql_parts.extend(match.group(0) for match in matches)
    return "\n".join(sql_parts)


def seed_region_codes(text: str) -> list[str]:
    match = re.search(r"insert\s+into\s+public\.regions\s*\([^)]*\)\s*values\s*(.*?);", text, re.I | re.S)
    if not match:
        raise AssertionError("seed insert for public.regions not found")
    return re.findall(r"\(\s*'([^']+)'", match.group(1))


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
    # 마이그레이션 history 정합: 후속 migration 의 ADD CONSTRAINT 가 기존
    # user_sports_grade_check 를 덮어쓰므로 최신 정의를 기준으로 비교한다.
    sql_users = user_sports_grade_constraint_history()
    sql_orgs = read(SQL_ORGS)
    seed = read(SQL_SEED)

    assert_same(
        "sports",
        ("Dart Sport", dart_enum(dart, "Sport")),
        ("TypeScript SPORTS", ts_const_array(ts, "SPORTS")),
        ("SQL sport", sql_enum_after_history(sql_users, "sport")),
    )
    # 등급 라벨은 DB 에 없다(코드가 정본). Dart↔TS 두 벌이 어긋나면 같은 등급이
    # 화면마다 다른 이름으로 보이므로 여기서 막는다.
    assert_same(
        "grade labels",
        ("Dart gradeLabels", dart_const_map(dart, "gradeLabels")),
        ("TypeScript GRADE_LABELS", ts_record(ts, "GRADE_LABELS")),
    )
    assert_same(
        "sport labels",
        ("Dart sportLabels", dart_sport_label_map(dart)),
        ("TypeScript SPORT_LABELS", ts_record(ts, "SPORT_LABELS")),
    )
    assert_same(
        "tennis grades",
        ("Dart tennisGrades", dart_const_list(dart, "tennisGrades")),
        ("TypeScript TENNIS_GRADES", ts_const_array(ts, "TENNIS_GRADES")),
        ("SQL tennis grade check", sql_grade_check(sql_users, "tennis")),
    )
    assert_same(
        "futsal grades",
        ("Dart futsalGrades", dart_const_list(dart, "futsalGrades")),
        ("TypeScript FUTSAL_GRADES", ts_const_array(ts, "FUTSAL_GRADES")),
        ("SQL futsal grade check", sql_grade_check(sql_users, "futsal")),
    )
    assert_same(
        "tennis orgs",
        ("Dart tennisOrgs", dart_const_list(dart, "tennisOrgs")),
        ("TypeScript TENNIS_ORGS", ts_const_array(ts, "TENNIS_ORGS")),
        ("SQL tennis_org", sql_enum(sql_orgs, "tennis_org")),
    )
    assert_same(
        "region codes",
        ("Dart regionCodes", dart_const_list(dart, "regionCodes")),
        ("TypeScript REGION_CODES", ts_const_array(ts, "REGION_CODES")),
        ("seed public.regions", seed_region_codes(seed)),
    )
    assert_same(
        "entry fee units",
        ("TypeScript ENTRY_FEE_UNITS", ts_const_array(ts, "ENTRY_FEE_UNITS")),
        ("SQL entry_fee_unit check", sql_entry_fee_units(sql_orgs)),
    )
    # 라벨은 등급 코드 전체를 덮어야 한다. 등급을 추가하고 라벨을 빠뜨리면 화면에
    # 코드가 그대로 노출되고, 폐기 등급이 라벨에만 남으면 유령 선택지가 된다.
    assert_same(
        "grade label coverage",
        (
            "grade codes",
            sorted(dart_const_list(dart, "tennisGrades") + dart_const_list(dart, "futsalGrades")),
        ),
        (
            "gradeLabels keys",
            sorted(entry.split("=", 1)[0] for entry in dart_const_map(dart, "gradeLabels")),
        ),
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"❌ enum consistency failed:\n{exc}", file=sys.stderr)
        raise SystemExit(1)
