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


def seed_grades() -> list[tuple[str, str, str, int]]:
    """마이그레이션의 public.grades seed 를 누적해 (sport, code, label, sort_order) 로.

    등급 추가·개명은 이제 CHECK 교체가 아니라 이 테이블의 INSERT 로 한다(JY-146 P3-a).
    같은 (sport, code) 가 여러 마이그레이션에 나오면 나중 것이 정본이다.
    한계: DELETE·개별 UPDATE 는 반영하지 않는다(폐기는 is_active=false 정책이라
    행이 사라지지 않는다).
    """
    rows: dict[tuple[str, str], tuple[str, str, str, int]] = {}
    insert_pattern = re.compile(
        r"insert\s+into\s+public\.grades\s*\([^)]*\)\s*values\s*(.*?)(?:on\s+conflict|;)",
        re.I | re.S,
    )
    # (sport, code, label, sort_order[, ...]) — 뒤에 컬럼이 더 붙어도(is_active 등) 읽는다.
    value_pattern = re.compile(
        r"\(\s*'([^']+)'\s*,\s*'([^']+)'\s*,\s*'([^']+)'\s*,\s*(\d+)\s*[,)]"
    )
    tuple_start = re.compile(r"\(\s*'")
    label_update = re.compile(
        r"update\s+public\.grades\s+set\s+label_ko\s*=\s*'([^']+)'(.*?);",
        re.I | re.S,
    )
    for path in sorted(SQL_MIGRATIONS.glob("*.sql")):
        migration = read(path)
        for block in insert_pattern.finditer(migration):
            values = block.group(1)
            parsed = value_pattern.findall(values)
            # 인식 못 한 튜플이 있으면 조용히 빠뜨리지 말고 실패한다. seed 형식이 바뀌면
            # 새 등급이 통째로 무시된 채 게이트가 PASS 하는 게 가장 위험하다.
            if len(parsed) != len(tuple_start.findall(values)):
                raise AssertionError(
                    f"{path.name}: public.grades seed 튜플을 전부 해석하지 못했다 "
                    f"(해석 {len(parsed)} / 발견 {len(tuple_start.findall(values))})"
                )
            for sport, code, label, order in parsed:
                rows[(sport, code)] = (sport, code, label, int(order))
        # 라벨만 바꾸는 후속 마이그레이션도 정본이다.
        for match in label_update.finditer(migration):
            new_label, where = match.group(1), match.group(2)
            sport = re.search(r"sport\s*=\s*'([^']+)'", where)
            code = re.search(r"code\s*=\s*'([^']+)'", where)
            if not sport or not code:
                raise AssertionError(
                    f"{path.name}: grades 라벨 UPDATE 의 대상을 (sport, code) 로 특정하지 못했다"
                )
            key = (sport.group(1), code.group(1))
            if key in rows:
                existing = rows[key]
                rows[key] = (existing[0], existing[1], new_label, existing[3])
    if not rows:
        raise AssertionError("public.grades seed 를 한 건도 찾지 못했다")
    # 앱은 라벨을 code 단일 키로 들고 있다(gradeLabels). 종목 간 code 가 겹치면 한쪽
    # 라벨이 다른 종목까지 덮어쓰므로 정본 단계에서 막는다.
    codes: dict[str, str] = {}
    for sport, code, _label, _order in rows.values():
        if code in codes and codes[code] != sport:
            raise AssertionError(
                f"grades: code '{code}' 가 {codes[code]}·{sport} 두 종목에 있다 "
                "(앱 라벨 맵이 code 단일 키라 서로 덮어쓴다)"
            )
        codes[code] = sport
    return sorted(rows.values(), key=lambda row: (row[0], row[3]))


def seed_grade_codes(sport: str) -> list[str]:
    return [row[1] for row in seed_grades() if row[0] == sport]


def seed_grade_label_entries() -> list[str]:
    """Dart/TS 라벨 맵과 같은 표기('code=label')로. 순서는 종목·sort_order."""
    return [f"{row[1]}={row[2]}" for row in seed_grades()]


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
    sql_users = read(SQL_USERS)
    sql_orgs = read(SQL_ORGS)
    seed = read(SQL_SEED)

    assert_same(
        "sports",
        ("Dart Sport", dart_enum(dart, "Sport")),
        ("TypeScript SPORTS", ts_const_array(ts, "SPORTS")),
        ("SQL sport", sql_enum_after_history(sql_users, "sport")),
    )
    # 등급 라벨의 정본은 public.grades 다(JY-146 P3-a). 클라 상수는 캐시이므로
    # seed 와 어긋나면 같은 등급이 화면마다 다른 이름으로 보인다.
    # 맵 자체의 나열 순서는 화면에 영향이 없어(등급 순서는 아래 코드 목록이 결정)
    # 정렬해 비교한다. 값이 다르거나 키가 빠지면 그대로 걸린다.
    assert_same(
        "grade labels",
        ("seed public.grades", sorted(seed_grade_label_entries())),
        ("Dart 폴백 gradeLabels", sorted(dart_const_map(dart, "_kFallbackGradeLabels"))),
        ("TypeScript GRADE_LABELS", sorted(ts_record(ts, "GRADE_LABELS"))),
    )
    assert_same(
        "sport labels",
        ("Dart sportLabels", dart_sport_label_map(dart)),
        ("TypeScript SPORT_LABELS", ts_record(ts, "SPORT_LABELS")),
    )
    assert_same(
        "tennis grades",
        ("Dart 폴백 tennisGrades", dart_const_list(dart, "_kFallbackTennisGrades")),
        ("TypeScript TENNIS_GRADES", ts_const_array(ts, "TENNIS_GRADES")),
        ("seed public.grades (tennis)", seed_grade_codes("tennis")),
    )
    assert_same(
        "futsal grades",
        ("Dart 폴백 futsalGrades", dart_const_list(dart, "_kFallbackFutsalGrades")),
        ("TypeScript FUTSAL_GRADES", ts_const_array(ts, "FUTSAL_GRADES")),
        ("seed public.grades (futsal)", seed_grade_codes("futsal")),
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
            sorted(
                dart_const_list(dart, "_kFallbackTennisGrades")
                + dart_const_list(dart, "_kFallbackFutsalGrades")
            ),
        ),
        (
            "gradeLabels keys",
            sorted(
                entry.split("=", 1)[0]
                for entry in dart_const_map(dart, "_kFallbackGradeLabels")
            ),
        ),
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"❌ enum consistency failed:\n{exc}", file=sys.stderr)
        raise SystemExit(1)
