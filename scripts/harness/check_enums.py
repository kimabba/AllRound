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


def strip_sql_comments(sql: str) -> str:
    """SQL 주석(`--`, `/* */`)을 지운다. 문자열 리터럴 안의 내용은 그대로 둔다.

    주석에 적힌 문장 예시("-- update public.grades set …")를 실제 문장으로 오인하면
    게이트가 엉뚱한 곳에서 실패한다. 줄 수를 보존하려고 개행은 남긴다.
    """
    out: list[str] = []
    index, length = 0, len(sql)
    while index < length:
        char = sql[index]
        if char == "'":  # 문자열 리터럴 — '' 이스케이프까지 통과시킨다.
            cursor = index + 1
            while cursor < length:
                if sql[cursor] == "'":
                    if cursor + 1 < length and sql[cursor + 1] == "'":
                        cursor += 2
                        continue
                    break
                cursor += 1
            out.append(sql[index : cursor + 1])
            index = cursor + 1
            continue
        if sql.startswith("--", index):
            while index < length and sql[index] != "\n":
                index += 1
            continue
        if sql.startswith("/*", index):
            end = sql.find("*/", index + 2)
            end = length if end < 0 else end + 2
            out.append("\n" * sql.count("\n", index, end))
            index = end
            continue
        out.append(char)
        index += 1
    return "".join(out)


def mask_string_literals(sql: str) -> str:
    """SQL 문자열 리터럴을 같은 길이의 플레이스홀더로 바꾼다. 리터럴 경계는 보존한다.

    정규식으로 SQL 을 다루면 문자열 리터럴 **안**의 텍스트를 코드로 오인한다. 예:
    `label_ko = 'sort_order=9'` 에서 리터럴 안 `sort_order=9` 를 setter 로 집어 정본을
    오염시켰고(codex 9차), `E'a\\';b'` 안의 `;` 가 문장 경계를 깨뜨렸다(codex 10차).
    길이를 보존하므로 원본과 오프셋이 일치해, 필요한 리터럴 값은 원본에서 다시 뽑는다.

    처리: `'…'`('' 이스케이프), `E'…'`(백슬래시 이스케이프), `$tag$…$tag$`(dollar-quote).
    dollar-quote 본문은 통째로 가려지므로, 그 안의 grades 쓰기는 별도로 검사한다
    (mask 만으로는 함수·DO 본문의 카탈로그 변경을 놓친다)."""
    out: list[str] = []
    index, length = 0, len(sql)
    while index < length:
        char = sql[index]
        # dollar-quote: $tag$ … $tag$ (tag 는 비어 있거나 식별자)
        dollar = re.match(r"\$[A-Za-z_]\w*\$|\$\$", sql[index:])
        if char == "$" and dollar:
            tag = dollar.group(0)
            close = sql.find(tag, index + len(tag))
            close = length if close < 0 else close
            body = close - (index + len(tag))
            out.append(tag + "\x01" * max(body, 0) + (tag if close < length else ""))
            index = (close + len(tag)) if close < length else length
            continue
        # E'…' 는 백슬래시로 따옴표를 이스케이프한다. 일반 '…' 는 '' 로.
        estring = char in "Ee" and index + 1 < length and sql[index + 1] == "'"
        if char == "'" or estring:
            quote_at = index + 1 if estring else index
            cursor = quote_at + 1
            while cursor < length:
                if estring and sql[cursor] == "\\":
                    cursor += 2
                    continue
                if sql[cursor] == "'":
                    if not estring and cursor + 1 < length and sql[cursor + 1] == "'":
                        cursor += 2
                        continue
                    break
                cursor += 1
            prefix = "E" if estring else ""
            out.append(prefix + "'" + "\x01" * (cursor - quote_at - 1) + "'")
            index = cursor + 1
            continue
        out.append(char)
        index += 1
    return "".join(out)


def dollar_quote_bodies(sql: str) -> list[str]:
    """`$tag$…$tag$` 본문들을 원문에서 뽑는다(함수·DO 블록). 여는 태그부터 짝짓는다."""
    bodies: list[str] = []
    index, length = 0, len(sql)
    while index < length:
        opener = re.match(r"\$[A-Za-z_]\w*\$|\$\$", sql[index:])
        if sql[index] == "$" and opener:
            tag = opener.group(0)
            close = sql.find(tag, index + len(tag))
            if close < 0:
                break
            bodies.append(sql[index + len(tag) : close])
            index = close + len(tag)
            continue
        index += 1
    return bodies


def split_sql_statements(sql: str) -> list[str]:
    """`;` 로 문장을 나눈다. 문자열 리터럴 안의 `;` 는 경계가 아니다.

    문장 종류를 tail 캡처로 훑으면 앞 문장의 tail 이 뒤 문장을 삼킨다 — 예: 한 줄에
    `INSERT … VALUES (…); TRUNCATE public.grades;` 를 쓰면 TRUNCATE 가 앞 INSERT 의
    200자 tail 안에 들어가 별도 문장으로 안 잡혔다(codex 9차). 문장 단위로 나누면 삼킴이
    불가능하다. 주석은 호출 전에 제거한다(리터럴은 보존)."""
    masked = mask_string_literals(sql)
    statements: list[str] = []
    start = 0
    for match in re.finditer(r";", masked):
        statements.append(sql[start : match.start()])
        start = match.end()
    if sql[start:].strip():
        statements.append(sql[start:])
    return statements


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


def seed_grades(active_only: bool = True) -> list[tuple[str, str, str, int]]:
    """마이그레이션의 public.grades seed 를 누적해 (sport, code, label, sort_order) 로.

    등급 추가·개명은 이제 CHECK 교체가 아니라 이 테이블의 INSERT 로 한다(JY-146 P3-a).
    같은 (sport, code) 가 여러 마이그레이션에 나오면 나중 것이 정본이고,
    `is_active` 는 seed 의 5번째 컬럼과 후속 UPDATE 를 반영한다.

    active_only=True 면 폐기 등급을 뺀다 — 클라 폴백의 선택지 목록과 맞추기 위해서다.
    라벨 비교는 폐기분까지 포함해야 하므로 False 로 부른다.
    한계: DELETE 는 반영하지 않는다(폐기는 is_active=false 정책이라 행이 사라지지 않는다).
    """
    rows: dict[tuple[str, str], tuple[str, str, str, int, bool]] = {}
    insert_pattern = re.compile(
        r"insert\s+into\s+public\.grades\s*\([^)]*\)\s*values\s*(.*?)(?:on\s+conflict|;)",
        re.I | re.S,
    )
    # (sport, code, label, sort_order[, is_active]) — 라벨 안의 이스케이프된 작은따옴표('')도
    # 허용한다. 다섯 번째 컬럼이 있으면 활성 여부로 읽는다.
    quoted = r"'((?:[^']|'')*)'"
    value_pattern = re.compile(
        rf"\(\s*{quoted}\s*,\s*{quoted}\s*,\s*{quoted}\s*,\s*(\d+)"
        r"(?:\s*,\s*(true|false))?\s*[,)]",
        re.I,
    )
    tuple_start = re.compile(r"\(\s*'")
    setter_update = re.compile(
        r"update\s+(?:only\s+)?public\.grades\s+set\s+(.*?)\s+where\s+(.*?);",
        re.I | re.S,
    )
    # WHERE 는 정확히 한 행을 지목해야 한다. `sport='x' or code='y'` 처럼 여러 행을 건드리면
    # 한 행만 반영한 셈이 돼 나머지가 조용히 어긋난다.
    single_row_where = re.compile(
        rf"^\s*sport\s*=\s*{quoted}\s+and\s+code\s*=\s*{quoted}\s*$", re.I
    )
    # grades 를 **쓰는** 문장은 전부 이 파서가 소화해야 한다. 지원하지 않는 문법을
    # 조용히 넘기면 카탈로그가 갈라져도 게이트가 PASS 한다 — 가장 위험한 실패다(fail-open).
    # 그래서 fail-closed 로 간다: 쓰기 동사 + grades 가 문장 어디에든 나오면(CTE·서브쿼리
    # 포함) 검사하고, 인식 못 하는 형태는 거부한다. quoted identifier(`"grades"`,
    # `"public"."grades"`)와 스키마 생략도 커버한다. `... from public.grades` 같은
    # 읽기는 쓰기 동사가 아니라 대상이 아니다.
    grades_write = re.compile(
        r"\b(insert\s+into|update|delete\s+from|merge\s+into|truncate(?:\s+table)?)\s+"
        r'(?:only\s+)?(?:"?public"?\s*\.\s*)?"?grades"?\b',
        re.I | re.S,
    )
    for path in sorted(SQL_MIGRATIONS.glob("*.sql")):
        raw = read(path)
        # dollar-quote(함수·DO) 본문은 mask 로 통째로 가려지므로 seed 문장 검사에서 빠진다.
        # 그 안에서 grades 를 쓰면 파서가 반영 못 하니, 본문을 따로 훑어 fail-closed 한다.
        for body in dollar_quote_bodies(strip_sql_comments(raw)):
            if grades_write.search(mask_string_literals(body)):
                raise AssertionError(
                    f"{path.name}: dollar-quote(함수/DO) 본문에서 public.grades 를 쓴다. "
                    "seed 파서가 반영하지 못하므로 마이그레이션 최상위 문장으로 표현하라."
                )
        # SQL 주석 안의 문장 예시를 실제 문장으로 오인하지 않는다(문자열 리터럴은 보존).
        migration = strip_sql_comments(raw)
        updates_seen = 0
        for statement in split_sql_statements(migration):
            match = grades_write.search(mask_string_literals(statement))
            if not match:
                continue
            kind = re.sub(r"\s+", " ", match.group(1)).lower()
            if kind == "insert into":
                if not re.search(r"\)\s*values\b", statement, re.I):
                    raise AssertionError(
                        f"{path.name}: public.grades INSERT 가 VALUES 형식이 아니다. "
                        "seed 파서가 반영하지 못하므로 VALUES 로 쓰거나 파서를 확장하라."
                    )
            elif kind == "update":
                updates_seen += 1
            elif kind.startswith("truncate"):
                raise AssertionError(
                    f"{path.name}: public.grades 를 TRUNCATE 한다. seed 파서가 반영하지 "
                    "못하며, user_sports 의 FK 도 깨진다(폐기는 is_active=false 정책이다)."
                )
            else:
                raise AssertionError(
                    f"{path.name}: public.grades 에 대한 {kind.upper()} 는 seed 파서가 "
                    "반영하지 못한다(폐기는 is_active=false 정책이다)."
                )
        if updates_seen != len(setter_update.findall(migration)):
            raise AssertionError(
                f"{path.name}: public.grades UPDATE {updates_seen} 건 중 "
                f"{len(setter_update.findall(migration))} 건만 해석했다 "
                "(`update public.grades set … where …;` 형식으로 맞춰라)."
            )
        for block in insert_pattern.finditer(migration):
            values = block.group(1)
            parsed = value_pattern.findall(values)
            # 인식 못 한 튜플이 있으면 조용히 빠뜨리지 말고 실패한다. seed 형식이 바뀌면
            # 새 등급이 통째로 무시된 채 게이트가 PASS 하는 게 가장 위험하다.
            if len(parsed) != len(tuple_start.findall(values)):
                raise AssertionError(
                    f"{path.name}: public.grades seed 튜플을 전부 해석하지 못했다 "
                    f"(해석 {len(parsed)} / 발견 {len(tuple_start.findall(values))}). "
                    "컬럼 순서를 (sport, code, label_ko, sort_order[, is_active]) 로 맞춰라."
                )
            for sport, code, label, order, active in parsed:
                rows[(sport, code)] = (
                    sport,
                    code,
                    label.replace("''", "'"),
                    int(order),
                    active.lower() != "false",
                )
        # 라벨 개명·폐기 처리도 정본이다.
        for match in setter_update.finditer(migration):
            setters, where = match.group(1), match.group(2)
            # 리터럴을 마스킹한 뒤 코드를 찾는다 — 라벨 값 안의 `sort_order=9` 같은 텍스트를
            # setter 로 오인하면 정본이 오염된다(codex 9차). 라벨 **값**은 원본에서 뽑는다.
            masked = mask_string_literals(setters)
            new_label = re.search(rf"label_ko\s*=\s*{quoted}", setters)
            new_active = re.search(r"is_active\s*=\s*(true|false)", masked, re.I)
            new_order = re.search(r"sort_order\s*=\s*(\d+)", masked, re.I)
            # 키(sport·code) 자체를 옮기는 UPDATE 는 누적 규칙이 달라진다. 반영한 척하지 말고 막는다.
            if re.search(r"\b(sport|code)\s*=", masked, re.I):
                raise AssertionError(
                    f"{path.name}: grades UPDATE 가 sport·code 를 바꾼다. "
                    "seed 파서가 키 이동을 추적하지 못하므로 새 행 INSERT 로 표현하라."
                )
            # 대상 컬럼의 **모든 출현**이 `컬럼 = 리터럴` 로 소비돼야 한다. 하나라도 다른
            # 형태면(계산식 `sort_order + 1`, 행 대입 `(sort_order, is_active) = (9, false)`)
            # 파서가 결과를 계산할 수 없다. 스칼라 하나만 인식됐다고 넘어가면, 같은 SET 절에
            # 섞인 행 대입이 통째로 무시된 채 게이트가 PASS 한다.
            patterns = {
                "label_ko": rf"label_ko\s*=\s*{quoted}",
                "is_active": r"is_active\s*=\s*(?:true|false)\b",
                "sort_order": r"sort_order\s*=\s*\d+",
            }
            # 마스킹된 텍스트에서 센다 — 리터럴 안의 컬럼명(`'sort_order=1'`)을 세면
            # 출현·해석 카운트가 어긋나 오탐/누락이 난다.
            for column, supported in patterns.items():
                mentions = len(re.findall(rf"\b{column}\b", masked, re.I))
                consumed = len(re.findall(supported, masked, re.I))
                if mentions != consumed:
                    raise AssertionError(
                        f"{path.name}: grades UPDATE 의 SET '{setters.strip()}' 에서 "
                        f"{column} 을 해석하지 못했다(출현 {mentions} / 해석 {consumed}). "
                        "`컬럼 = 리터럴` 형태로만 써라(계산식·행 대입은 지원하지 않는다)."
                    )
            if not new_label and not new_active and not new_order:
                # 대상 컬럼이 SET 절에 나왔는데 하나도 못 읽었다면 지원하지 않는 대입 형태다
                # (예: 행 대입 `set (label_ko, sort_order) = ('x', 9)`). 조용히 넘기면
                # DB 카탈로그만 바뀌고 폴백과의 드리프트를 게이트가 놓친다.
                if re.search(r"\b(label_ko|is_active|sort_order)\b", masked, re.I):
                    raise AssertionError(
                        f"{path.name}: grades UPDATE 의 SET '{setters.strip()}' 를 해석하지 "
                        "못했다. `컬럼 = 리터럴` 형태로 써라(행 대입은 지원하지 않는다)."
                    )
                continue
            if not single_row_where.match(where.strip()):
                raise AssertionError(
                    f"{path.name}: grades UPDATE 의 WHERE '{where.strip()}' 가 "
                    "`sport = '…' and code = '…'` 형태가 아니다(여러 행을 건드리면 "
                    "일부만 반영돼 조용히 어긋난다)."
                )
            matched = single_row_where.match(where.strip())
            key = (matched.group(1), matched.group(2))
            if key in rows:
                sport_v, code_v, label_v, order_v, active_v = rows[key]
                if new_label:
                    label_v = new_label.group(1).replace("''", "'")
                if new_active:
                    active_v = new_active.group(1).lower() != "false"
                if new_order:
                    order_v = int(new_order.group(1))
                rows[key] = (sport_v, code_v, label_v, order_v, active_v)
    if not rows:
        raise AssertionError("public.grades seed 를 한 건도 찾지 못했다")
    # 앱은 라벨을 code 단일 키로 들고 있다(gradeLabels). 종목 간 code 가 겹치면 한쪽
    # 라벨이 다른 종목까지 덮어쓰므로 정본 단계에서 막는다.
    codes: dict[str, str] = {}
    for sport, code, _label, _order, _active in rows.values():
        if code in codes and codes[code] != sport:
            raise AssertionError(
                f"grades: code '{code}' 가 {codes[code]}·{sport} 두 종목에 있다 "
                "(앱 라벨 맵이 code 단일 키라 서로 덮어쓴다)"
            )
        codes[code] = sport
    selected = [row[:4] for row in rows.values() if row[4] or not active_only]
    return sorted(selected, key=lambda row: (row[0], row[3]))


def seed_grade_codes(sport: str) -> list[str]:
    """활성 등급만 — 클라 폴백의 선택지 목록과 대응한다."""
    return [row[1] for row in seed_grades() if row[0] == sport]


def seed_grade_label_entries() -> list[str]:
    """라벨은 폐기 등급까지 필요하다(과거 데이터 표시). 표기는 'code=label'."""
    return [f"{row[1]}={row[2]}" for row in seed_grades(active_only=False)]


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
