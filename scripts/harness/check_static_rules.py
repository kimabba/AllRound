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


# 종목·등급의 한글 라벨은 정본 두 파일에만 있어야 한다. 화면 코드가 라벨을 직접
# 적으면 등급 개편 때 그 줄만 남아 조용히 갈라진다(JY-146).
#
# 규칙: 문자열 리터럴 **전체**가 라벨과 같으면 위반. 리터럴 안에 라벨이 들어 있기만
# 한 건(예: '서울 오픈 테니스' 같은 대회명, 주석 문장) 잡지 않는다. 코드값이 같은 줄에
# 있는지는 보지 않는다 — 여러 줄에 걸친 형태(`Text('테니스')`)와 라벨만 나열한
# 형태(`['무관', '1년 미만', …]`)가 실제 재발 경로였다.
LABEL_SSOT_FILES = {
    "app/lib/utils/grade_labels.dart",
    "supabase/functions/_shared/enums.ts",
}
# 외부 텍스트(사용자 발화·크롤링 원문)를 한국어로 매칭해 코드값을 얻는 입력 파서.
# 라벨을 표시하는 게 아니라 인식하는 쪽이라 정본 파생으로 대체할 수 없다.
LABEL_SCAN_EXEMPT_FILES = {
    "supabase/functions/_shared/intent.ts",
}
LABEL_SCAN_EXEMPT_DIRS = ("supabase/functions/_shared/crawler/",)
LABEL_SCAN_ROOTS = [("app/lib", "*.dart"), ("supabase/functions", "*.ts")]
# 정본(grade_labels.dart / enums.ts)의 라벨 값과 일치해야 한다.
FORBIDDEN_LABELS = {
    "테니스",
    "풋살",
    "1년 미만",
    "1~3년",
    "3~5년",
    "5년 이상",
    "입문",
    "초급",
    "중급",
    "고급",
    "선출",
    # '무관'(anyGradeLabel)은 성별·나이대 선택지에도 쓰이는 범용어라 제외한다.
    # 등급 목록을 직접 나열하면 나머지 라벨에서 걸린다.
}
STRING_LITERAL = re.compile(r"'([^'\\\n]*)'|\"([^\"\\\n]*)\"")


def check_sport_grade_label_hardcode() -> None:
    violations: list[str] = []
    for relative_root, pattern in LABEL_SCAN_ROOTS:
        for path in (ROOT / relative_root).rglob(pattern):
            relative = path.relative_to(ROOT).as_posix()
            if relative in LABEL_SSOT_FILES or relative in LABEL_SCAN_EXEMPT_FILES:
                continue
            if relative.startswith(LABEL_SCAN_EXEMPT_DIRS):
                continue
            if path.name.endswith(("_test.dart", "_test.ts")) or "/tests/" in relative:
                continue
            for line_number, line in enumerate(
                path.read_text(encoding="utf-8").splitlines(), start=1
            ):
                for match in STRING_LITERAL.finditer(line):
                    literal = match.group(1) if match.group(1) is not None else match.group(2)
                    if literal in FORBIDDEN_LABELS:
                        violations.append(f"{relative}:{line_number}: '{literal}' — {line.strip()}")
    if violations:
        fail(
            "라벨 재하드코딩(JY-146): 종목·등급 라벨을 코드에 직접 적었다.\n"
            "Dart 는 sportLabel*/gradeLabel/anyGradeLabel, TS 는 SPORT_LABELS/GRADE_LABELS 를 쓴다.\n"
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
