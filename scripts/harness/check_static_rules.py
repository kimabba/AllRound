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


def string_literals(line: str) -> list[str]:
    """한 줄에서 문자열 리터럴(작은/큰따옴표·백틱)을 뽑는다.

    줄 주석(`//`) 이후는 코드가 아니므로 무시하고, 따옴표 **안**의 `//`(URL 등)는
    주석으로 오인하지 않는다. 닫히지 않은 따옴표(여러 줄 문자열)를 만나면 그 줄은 포기한다.
    """
    literals: list[str] = []
    index, length = 0, len(line)
    while index < length:
        char = line[index]
        if char == "/" and index + 1 < length and line[index + 1] == "/":
            break
        if char in "'\"`":
            cursor = index + 1
            buffer: list[str] = []
            while cursor < length and line[cursor] != char:
                if line[cursor] == "\\":
                    cursor += 2
                    continue
                buffer.append(line[cursor])
                cursor += 1
            if cursor >= length:
                break
            literals.append("".join(buffer))
            index = cursor + 1
            continue
        index += 1
    return literals


def forbidden_labels() -> set[str]:
    """정본(grade_labels.dart)의 등급·종목 라벨 + 폐기 라벨."""
    text = read(LABEL_SSOT_DART)
    labels: set[str] = set()
    grade_block = re.search(r"const gradeLabels\s*=\s*<String, String>\{(.*?)\};", text, re.S)
    sport_block = re.search(r"const sportLabels\s*=\s*<Sport, String>\{(.*?)\};", text, re.S)
    if not grade_block or not sport_block:
        fail(f"{LABEL_SSOT_DART}: gradeLabels/sportLabels 선언을 찾지 못했다 (가드가 무력해진다)")
    labels |= {m.group(2) for m in re.finditer(r"'([^']+)'\s*:\s*'([^']+)'", grade_block.group(1))}
    labels |= {
        m.group(2) for m in re.finditer(r"Sport\.(\w+)\s*:\s*'([^']+)'", sport_block.group(1))
    }
    if not labels:
        fail(f"{LABEL_SSOT_DART}: 라벨을 한 건도 추출하지 못했다 (가드가 무력해진다)")
    return (labels | RETIRED_LABELS) - LABEL_SCAN_IGNORED


def label_violations_in_line(line: str, labels: set[str]) -> list[str]:
    return [literal for literal in string_literals(line) if literal in labels]


# 가드가 잡아야 하는 형태 / 통과시켜야 하는 형태. 규칙을 바꾸면 여기서 먼저 깨진다.
GUARD_MUST_BLOCK = [
    "label: Text('테니스'),",
    "static const _g = ['무관', '1년 미만', '1~3년'];",
    'const z = sport == "tennis" ? "테니스" : "풋살";',
    "  return '테니스';",
    "const heading = `풋살`;",
    "static const _tennisGrades = ['무관', '신입', '5부', '4부', '3부', '2부', '1부'];",
]
GUARD_MUST_ALLOW = [
    "const t = '서울 오픈 테니스';",
    "// label: Text('테니스') 였던 자리",
    "const u = {'url': 'https://x.test/a', 'name': '광주 오픈'};",
    "if (/(테니스|tennis)/i.test(text)) return 'tennis';",
    "const sports = ['tennis', 'futsal'];",
]


def check_sport_grade_label_hardcode() -> None:
    labels = forbidden_labels()

    for sample in GUARD_MUST_BLOCK:
        if not label_violations_in_line(sample, labels):
            fail(f"라벨 가드 자가검증 실패 — 잡아야 할 형태를 놓쳤다: {sample}")
    for sample in GUARD_MUST_ALLOW:
        found = label_violations_in_line(sample, labels)
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
            for line_number, line in enumerate(
                path.read_text(encoding="utf-8").splitlines(), start=1
            ):
                for literal in label_violations_in_line(line, labels):
                    violations.append(f"{relative}:{line_number}: '{literal}' — {line.strip()}")
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
