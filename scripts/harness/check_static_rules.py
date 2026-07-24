#!/usr/bin/env python3
"""Cheap repository rules that prevent harness/rule drift."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

ROOT_RULE_LIMITS = {
    "AGENTS.md": 100,
    "CLAUDE.md": 80,
}

REQUIRED_RULE_DOCS = [
    "docs/rules/README.md",
    "docs/rules/PROJECT_CONTEXT.md",
    "docs/rules/CODING_RULES.md",
    "docs/rules/DOMAIN_RULES.md",
    "docs/rules/FRONTEND_RULES.md",
    "docs/rules/BACKEND_RULES.md",
    "docs/rules/DATABASE_RULES.md",
    "docs/rules/SECURITY_RULES.md",
    "docs/rules/SPEED_GUN_RULES.md",
    "docs/rules/HARNESS.md",
]

FORBIDDEN_ROOT_HEADINGS = [
    "## Project Overview",
    "## Tech Stack",
    "## Architecture",
    "## Environment Variables",
    "## Operational Notes",
]


def fail(message: str) -> None:
    print(f"❌ {message}", file=sys.stderr)
    raise SystemExit(1)


def read(relative: str) -> str:
    path = ROOT / relative
    if not path.exists():
        fail(f"missing required file: {relative}")
    return path.read_text(encoding="utf-8")


def check_root_file_lengths() -> None:
    for relative, limit in ROOT_RULE_LIMITS.items():
        text = read(relative)
        lines = text.splitlines()
        if len(lines) > limit:
            fail(f"{relative} is {len(lines)} lines; keep it <= {limit} lines and move detail into docs/rules/")
        for heading in FORBIDDEN_ROOT_HEADINGS:
            if heading in text:
                fail(f"{relative} contains long-form heading {heading!r}; move this content into docs/rules/")
        print(f"✓ {relative}: {len(lines)} lines <= {limit}")


def check_required_rule_docs() -> None:
    for relative in REQUIRED_RULE_DOCS:
        read(relative)
    print(f"✓ required rule docs present: {len(REQUIRED_RULE_DOCS)}")


def check_agents_rule_links() -> None:
    agents = read("AGENTS.md")
    missing = [relative for relative in REQUIRED_RULE_DOCS[1:] if f"`{relative}`" not in agents]
    if missing:
        fail("AGENTS.md load-on-demand map is missing: " + ", ".join(missing))
    print("✓ AGENTS.md references load-on-demand rule docs")


def check_github_templates() -> None:
    required = [
        ".github/pull_request_template.md",
        ".github/ISSUE_TEMPLATE/bug_report.yml",
        ".github/ISSUE_TEMPLATE/feature_task.yml",
        ".github/ISSUE_TEMPLATE/harness_task.yml",
        ".github/workflows/harness.yml",
    ]
    for relative in required:
        read(relative)
    print(f"✓ GitHub collaboration files present: {len(required)}")


def check_no_shell_background_wrappers_in_harness() -> None:
    run_all = read("scripts/harness/run_all.sh")
    if re.search(r"\b(nohup|disown|setsid)\b", run_all):
        fail("scripts/harness/run_all.sh should stay foreground and CI-friendly")
    print("✓ harness script is foreground/CI-friendly")


def check_pureform_literal_contracts() -> None:
    roots = [ROOT / "app/lib/screens", ROOT / "app/lib/widgets"]
    excluded_parts = {"admin"}
    excluded_names = {"speed_gun_screen_web.dart"}
    forbidden = [
        re.compile(r"BorderRadius\.circular\((?:13|14|15|18|20|24|28|32)\)"),
        re.compile(r"Size\.fromHeight\((?:44|50|52|54|56)\)"),
        re.compile(r"fixedSize:\s*const\s+Size\.square\((?:40|44)\)"),
    ]
    violations: list[str] = []
    for root in roots:
        for path in root.rglob("*.dart"):
            if excluded_parts.intersection(path.parts) or path.name in excluded_names:
                continue
            for line_number, line in enumerate(
                path.read_text(encoding="utf-8").splitlines(), start=1
            ):
                if any(pattern.search(line) for pattern in forbidden):
                    relative = path.relative_to(ROOT)
                    violations.append(f"{relative}:{line_number}: {line.strip()}")
    if violations:
        fail(
            "Pureform literal contract drift; use AppRadius/AppSizes tokens:\n"
            + "\n".join(violations)
        )
    print("✓ Pureform radius and fixed-control literals use shared tokens")


# 종목·등급의 한글 라벨은 정본에만 있어야 한다. 화면 코드가 라벨을 직접 적으면 등급
# 개편 때 그 줄만 남아 조용히 갈라진다(JY-146).
#
# 규칙: 문자열 리터럴 **전체**가 라벨과 같으면 위반. 리터럴 안에 라벨이 들어 있기만
# 한 건(대회명 '서울 오픈 테니스') 잡지 않는다. 코드값이 같은 줄에 있는지는 보지 않는다 —
# 여러 줄에 걸친 `Text('테니스')` 와 라벨만 나열한 `['무관', '1년 미만', …]` 가 실제
# 재발 경로였다.
#
# 금지 목록은 **정본을 파싱해서 만든다**. 여기에 라벨을 다시 적으면 가드 자신이 또 하나의
# 사본이 되어, 정본이 바뀔 때 가드만 뒤처진다.
LABEL_SSOT_DART = "app/lib/utils/grade_labels.dart"
LABEL_SSOT_FILES = {LABEL_SSOT_DART, "supabase/functions/_shared/enums.ts"}
# 외부 텍스트(사용자 발화)를 한국어로 매칭해 코드값을 얻는 입력 파서. 라벨을 표시하는 게
# 아니라 인식하는 쪽이라 정본 파생으로 대체할 수 없다. 크롤러 파서는 예외로 두지 않는다 —
# 출력용 라벨 하드코딩이 거기 들어가도 잡아야 한다.
LABEL_SCAN_EXEMPT_FILES = {"supabase/functions/_shared/intent.ts"}
LABEL_SCAN_ROOTS = [("app/lib", "*.dart"), ("supabase/functions", "*.ts")]
# 마이그 010 에서 폐기된 옛 테니스 부수체계. 정본에 없으니 파생할 수 없지만, 실제로
# 2026-07 까지 팀모집 UI 에 살아 있었다. 되돌아오면 막는다.
RETIRED_LABELS = {"신입", "5부", "4부", "3부", "2부", "1부"}
# '무관'(anyGradeLabel)은 성별·나이대 선택지에도 쓰이는 범용어라 제외한다. 등급 목록을
# 통째로 나열하면 나머지 라벨에서 걸린다.
LABEL_SCAN_IGNORED = {"무관"}


def string_literals(source: str) -> list[tuple[int, str]]:
    """소스에서 문자열 리터럴을 (시작 줄, 내용)으로 뽑는다.

    줄 주석(`//`) 이후는 코드가 아니므로 무시하고, 따옴표 **안**의 `//`(URL 등)는
    주석으로 오인하지 않는다. Dart 의 `'''` 블록과 TS 의 백틱 template literal 처럼
    여러 줄에 걸친 문자열도 끝까지 따라간다 — 줄 단위로만 보면 라벨을 여러 줄 문자열
    안에 넣는 것만으로 가드를 피할 수 있었다.
    """
    literals: list[tuple[int, str]] = []
    index, length, line_no = 0, len(source), 1
    while index < length:
        char = source[index]
        if char == "\n":
            line_no += 1
            index += 1
            continue
        if char == "/" and index + 1 < length and source[index + 1] == "/":
            while index < length and source[index] != "\n":
                index += 1
            continue
        if char == "/" and index + 1 < length and source[index + 1] == "*":
            # Dart 는 블록 주석 중첩을 허용한다. 첫 `*/` 에서 멈추면 아직 주석인 구간을
            # 코드로 오인해 오탐이 난다.
            depth, cursor = 1, index + 2
            while cursor < length and depth:
                if source.startswith("/*", cursor):
                    depth += 1
                    cursor += 2
                    continue
                if source.startswith("*/", cursor):
                    depth -= 1
                    cursor += 2
                    continue
                if source[cursor] == "\n":
                    line_no += 1
                cursor += 1
            index = cursor
            continue
        if char in "'\"`":
            # Dart 의 삼중 따옴표는 경계 자체가 세 글자다.
            delim = char * 3 if source.startswith(char * 3, index) else char
            multiline = len(delim) == 3 or delim == "`"
            start_line = line_no
            cursor = index + len(delim)
            buffer: list[str] = []
            embedded: list[tuple[int, str]] = []
            closed = False
            while cursor < length:
                if source.startswith(delim, cursor):
                    closed = True
                    break
                current = source[cursor]
                if current == "\\":
                    cursor += 2
                    continue
                # TS 템플릿 보간 `${…}` 안은 문자열이 아니라 코드다. 통째로 리터럴 취급하면
                # `${ok ? '테니스' : '풋살'}` 처럼 감싸는 것만으로 가드를 피할 수 있다.
                # (보간 안 문자열에 중괄호가 들어가는 경우까지는 세지 않는다 — 실코드에 없다.)
                if delim == "`" and source.startswith("${", cursor):
                    depth, scan, expr_line = 1, cursor + 2, line_no
                    while scan < length and depth:
                        if source[scan] == "{":
                            depth += 1
                        elif source[scan] == "}":
                            depth -= 1
                        elif source[scan] == "\n":
                            line_no += 1
                        scan += 1
                    embedded.append((expr_line, source[cursor + 2 : max(scan - 1, cursor + 2)]))
                    cursor = scan
                    continue
                if current == "\n":
                    # 한 줄 문자열은 줄을 넘지 않는다 — 따옴표가 아니라 아포스트로피다.
                    if not multiline:
                        break
                    line_no += 1
                buffer.append(current)
                cursor += 1
            if not closed:
                index += 1
                continue
            literals.append((start_line, "".join(buffer)))
            for expr_line, expression in embedded:
                for inner_line, inner in string_literals(expression):
                    literals.append((expr_line + inner_line - 1, inner))
            index = cursor + len(delim)
            continue
        index += 1
    return literals


def forbidden_labels() -> set[str]:
    """정본(grade_labels.dart)의 등급·종목 라벨 + 폐기 라벨."""
    text = read(LABEL_SSOT_DART)
    labels: set[str] = set()
    grade_block = re.search(
        r"const _kFallbackGradeLabels\s*=\s*<String, String>\{(.*?)\};", text, re.S
    )
    sport_block = re.search(r"const sportLabels\s*=\s*<Sport, String>\{(.*?)\};", text, re.S)
    if not grade_block or not sport_block:
        fail(
            f"{LABEL_SSOT_DART}: _kFallbackGradeLabels/sportLabels 선언을 찾지 못했다"
            " (가드가 무력해진다)"
        )
    labels |= {m.group(2) for m in re.finditer(r"'([^']+)'\s*:\s*'([^']+)'", grade_block.group(1))}
    labels |= {
        m.group(2) for m in re.finditer(r"Sport\.(\w+)\s*:\s*'([^']+)'", sport_block.group(1))
    }
    if not labels:
        fail(f"{LABEL_SSOT_DART}: 라벨을 한 건도 추출하지 못했다 (가드가 무력해진다)")
    return (labels | RETIRED_LABELS) - LABEL_SCAN_IGNORED


def label_violations(source: str, labels: set[str]) -> list[tuple[int, str]]:
    """(줄 번호, 금지 라벨) 목록. 여러 줄 문자열은 줄 단위로 쪼개 비교한다 —
    통째로 비교하면 `'''\\n입문\\n'''` 처럼 감싸는 것만으로 빠져나간다."""
    found: list[tuple[int, str]] = []
    literals = string_literals(source)
    for start_line, literal in literals:
        for offset, piece in enumerate(literal.split("\n")):
            if piece.strip() in labels:
                found.append((start_line + offset, piece.strip()))
    # Dart 는 인접한 문자열을 컴파일 시 하나로 합친다('테' '니스' == '테니스').
    # 같은 줄의 연속 리터럴을 이어붙인 것도 검사한다.
    per_line: dict[int, list[str]] = {}
    for start_line, literal in literals:
        if "\n" not in literal:
            per_line.setdefault(start_line, []).append(literal)
    for line_number, pieces in per_line.items():
        for start in range(len(pieces)):
            for end in range(start + 2, len(pieces) + 1):
                joined = "".join(pieces[start:end]).strip()
                if joined in labels:
                    found.append((line_number, joined))
    return found


# 가드가 잡아야 하는 형태 / 통과시켜야 하는 형태. 규칙을 바꾸면 여기서 먼저 깨진다.
GUARD_MUST_BLOCK = [
    "label: Text('테니스'),",
    "static const _g = ['무관', '1년 미만', '1~3년'];",
    'const z = sport == "tennis" ? "테니스" : "풋살";',
    "  return '테니스';",
    "const heading = `풋살`;",
    "static const _tennisGrades = ['무관', '신입', '5부', '4부', '3부', '2부', '1부'];",
    # 여러 줄 문자열에 숨긴 라벨. 줄 단위 스캔의 구멍이었다.
    "const doc = '''\n입문\n''';",
    "const tpl = `\n테니스\n`;",
    # TS 템플릿 보간 안은 코드다. 통째로 리터럴 취급하면 감싸는 것만으로 빠져나갔다.
    "const z = `${ok ? '입문' : '초급'}`;",
    # Dart 인접 문자열 연결은 컴파일 시 하나로 합쳐진다.
    "const s = '테' '니스';",
]
GUARD_MUST_ALLOW = [
    "const t = '서울 오픈 테니스';",
    "// label: Text('테니스') 였던 자리",
    "const u = {'url': 'https://x.test/a', 'name': '광주 오픈'};",
    "if (/(테니스|tennis)/i.test(text)) return 'tennis';",
    "const sports = ['tennis', 'futsal'];",
    # 여러 줄 문자열이어도 라벨이 문장 일부면 정상이다(부분 포함은 막지 않는다).
    "const doc = '''\n서울 오픈 테니스 대회 안내\n''';",
    # 중첩 블록 주석. 첫 */ 에서 멈추면 아직 주석인 구간을 코드로 오인한다.
    "/* 바깥 /* 안쪽 */ 아직 주석 '테니스' */ const x = 1;",
    # 보간 밖의 정적 부분은 문장이므로 부분 포함이다.
    "const msg = `${count}명이 테니스 대회에 참가`;",
]


def check_sport_grade_label_hardcode() -> None:
    labels = forbidden_labels()

    for sample in GUARD_MUST_BLOCK:
        if not label_violations(sample, labels):
            fail(f"라벨 가드 자가검증 실패 — 잡아야 할 형태를 놓쳤다: {sample}")
    for sample in GUARD_MUST_ALLOW:
        found = label_violations(sample, labels)
        if found:
            fail(f"라벨 가드 자가검증 실패 — 정상 코드를 막았다({found}): {sample}")

    violations: list[str] = []
    for relative_root, pattern in LABEL_SCAN_ROOTS:
        for path in (ROOT / relative_root).rglob(pattern):
            relative = path.relative_to(ROOT).as_posix()
            if relative in LABEL_SSOT_FILES or relative in LABEL_SCAN_EXEMPT_FILES:
                continue
            if path.name.endswith(("_test.dart", "_test.ts")) or "/tests/" in relative:
                continue
            source = path.read_text(encoding="utf-8")
            lines = source.splitlines()
            for line_number, literal in label_violations(source, labels):
                context = lines[line_number - 1].strip() if line_number <= len(lines) else ""
                violations.append(f"{relative}:{line_number}: '{literal}' — {context}")
    if violations:
        fail(
            "라벨 재하드코딩(JY-146): 종목·등급 라벨을 코드에 직접 적었다.\n"
            "Dart 는 sportLabel*/gradeLabel/anyGradeLabel, TS 는 SPORT_LABELS/GRADE_LABELS 를 쓴다.\n"
            + "\n".join(violations)
        )
    print(f"✓ 종목·등급 라벨이 정본 파일에서만 정의된다 (금지 라벨 {len(labels)}개, 자가검증 통과)")


def main() -> int:
    check_root_file_lengths()
    check_required_rule_docs()
    check_agents_rule_links()
    check_github_templates()
    check_no_shell_background_wrappers_in_harness()
    check_pureform_literal_contracts()
    check_sport_grade_label_hardcode()
    print("✅ static repository rules passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
