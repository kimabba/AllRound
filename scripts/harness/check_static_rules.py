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


# 종목·등급의 한글 라벨은 정본 두 파일에만 있어야 한다. 코드값 옆에 라벨을 직접
# 적으면(삼항·if 분기) 등급 개편 때 그 줄만 남아 조용히 갈라진다(JY-146).
LABEL_SSOT_FILES = {
    "app/lib/utils/grade_labels.dart",
    "supabase/functions/_shared/enums.ts",
}
# 사용자 발화에서 종목을 알아내는 키워드 매칭. 라벨 사용이 아니라 입력 파싱이다.
LABEL_SCAN_EXEMPT = {
    "supabase/functions/_shared/intent.ts",
}
LABEL_SCAN_ROOTS = [("app/lib", "*.dart"), ("supabase/functions", "*.ts")]
CODE_LABEL_PAIRS = [
    (
        "종목",
        re.compile(r"'(?:tennis|futsal)'"),
        re.compile(r"테니스|풋살"),
    ),
    (
        "등급",
        re.compile(r"'(?:under1y|y1to3|y3to5|over5y|intro|beginner|intermediate|advanced|elite)'"),
        re.compile(r"1년 미만|1~3년|3~5년|5년 이상|입문|초급|중급|고급|선출"),
    ),
]


def strip_line_comment(line: str) -> str:
    index = line.find("//")
    return line if index < 0 else line[:index]


def check_sport_grade_label_hardcode() -> None:
    violations: list[str] = []
    for relative_root, pattern in LABEL_SCAN_ROOTS:
        for path in (ROOT / relative_root).rglob(pattern):
            relative = path.relative_to(ROOT).as_posix()
            if relative in LABEL_SSOT_FILES or relative in LABEL_SCAN_EXEMPT:
                continue
            if "test" in path.name or "/tests/" in relative:
                continue
            for line_number, raw in enumerate(
                path.read_text(encoding="utf-8").splitlines(), start=1
            ):
                line = strip_line_comment(raw)
                for kind, code_pattern, label_pattern in CODE_LABEL_PAIRS:
                    if code_pattern.search(line) and label_pattern.search(line):
                        violations.append(f"{relative}:{line_number}: [{kind}] {raw.strip()}")
    if violations:
        fail(
            "라벨 재하드코딩(JY-146): 코드값 옆에 한글 라벨을 직접 적었다.\n"
            "Dart 는 sportLabel*/gradeLabel, TS 는 SPORT_LABELS/GRADE_LABELS 를 쓴다.\n"
            + "\n".join(violations)
        )
    print("✓ 종목·등급 라벨이 정본 파일에서만 정의된다")


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
