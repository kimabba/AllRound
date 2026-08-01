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


def check_tournament_closed_is_automation_only() -> None:
    """JY-151: 대회의 'closed' 는 크롤 dispatcher(날짜 기준 자동 마감)만 만든다.

    _shared/tournament_status.ts 의 되살리기(closed + 미래 start_date → published)는 이 전제
    위에서만 안전하다. 관리자가 UI 로 직접 closed 를 고를 수 있게 되면, 사람이 닫은 대회를
    다음 크롤이 조용히 되살린다. 그때는 auto/수동 구분 컬럼부터 만들어야 한다.
    """
    relative = "app/lib/screens/admin/tournament_edit_screen.dart"
    source = read(relative)
    values = set(re.findall(r"DropdownMenuItem\(\s*\n?\s*value:\s*'([a-z_]+)'", source))
    if not values:
        fail(f"{relative}: 대회 상태 드롭다운을 찾지 못했다 — 규칙이 무력화됐는지 확인할 것")
    if "closed" in values:
        fail(
            f"{relative}: 상태 드롭다운에 'closed' 를 추가했다.\n"
            "supabase/functions/_shared/tournament_status.ts 가 closed 를 '자동 마감'으로 보고 "
            "미래 대회를 되살린다 — 수동 마감을 도입하려면 auto/수동 구분을 먼저 넣을 것."
        )
    print(f"✓ 대회 상태 'closed' 는 자동화 전용 (드롭다운: {', '.join(sorted(values))})")


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
LABEL_SSOT_FILES = {LABEL_SSOT_DART}
# enums.ts 는 종목 라벨(SPORT_LABELS)의 정본이라 그 라벨로는 검사할 수 없다. 그러나 등급 라벨
# 사본(GRADE_LABELS)은 #319 로 없어졌으므로 **등급 라벨만** 검사해 재하드코딩을 잡는다.
# 심볼 이름 대조(check_grades_parity)는 이름만 바꾸면 우회되지만, 이 검사는 라벨 문자열 자체를
# 보므로 어떤 이름·형태로 되살려도 걸린다.
LABEL_GRADE_ONLY_FILES = {"supabase/functions/_shared/enums.ts"}
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


def decode_string_escapes(text: str) -> str:
    """Dart/TS 문자열 이스케이프를 실제 문자로 바꾼다. 라벨을 `\\uXXXX` 로 숨기는 우회 차단.

    커버: `\\uXXXX`, `\\u{XX..}`(Dart/JS), `\\xXX`(JS). 나머지(`\\n` 등)는 뒷문자만 남긴다 —
    라벨 매칭이 목적이라 정확한 제어문자 복원까지는 필요 없다. 잘못된 시퀀스는 원문 유지."""
    def replace(match: "re.Match[str]") -> str:
        brace, four, hexx, other = match.group(1), match.group(2), match.group(3), match.group(4)
        try:
            if brace is not None:
                return chr(int(brace, 16))
            if four is not None:
                return chr(int(four, 16))
            if hexx is not None:
                return chr(int(hexx, 16))
        except (ValueError, OverflowError):
            return match.group(0)
        return other

    # 백슬래시+줄종료는 줄 연속 — 결과 문자열에서 사라진다. `'테\<LF>니스'` == `테니스`.
    # 먼저 없애지 않으면 라벨이 줄종료로 쪼개져 검출을 피한다(codex 10차).
    # ECMAScript LineTerminatorSequence 전부를 다룬다: CRLF·LF·단독 CR·U+2028·U+2029
    # (LF 만 지우면 나머지 종료 문자로 우회할 수 있다, codex 11차).
    text = re.sub(r"\\(?:\r\n|[\n\r\u2028\u2029])", "", text)
    return re.sub(
        r"\\u\{([0-9a-fA-F]+)\}|\\u([0-9a-fA-F]{4})|\\x([0-9a-fA-F]{2})|\\(.)",
        replace,
        text,
    )


def _regex_context(source: str, slash: int) -> bool:
    """`source[slash]` 의 `/` 가 정규식 리터럴 시작인지(나눗셈이 아닌지) 보수적으로 본다.

    JS/TS 에서 `/` 는 값 뒤면 나눗셈, 그 외엔 정규식 시작이다. 직전 유의미 문자가
    값의 끝(식별자·닫는 괄호·숫자·따옴표)이 아니면 정규식으로 간주한다. Dart 에는 정규식
    리터럴이 없지만, Dart 의 나눗셈은 늘 값 뒤라 여기서 정규식으로 오인되지 않는다."""
    if slash + 1 < len(source) and source[slash + 1] in "/*":
        return False  # 주석이지 정규식이 아니다.
    j = slash - 1
    while j >= 0 and source[j] in " \t":
        j -= 1
    if j < 0:
        return True  # 파일·식 맨 앞.
    prev = source[j]
    # `)`·`]` 는 그룹/인덱싱 종료라 값 → 나눗셈.
    if prev in ")]":
        return False
    # 식별자로 끝나면 단어를 뽑아 본다. 값(변수)이면 나눗셈이지만, 키워드
    # (`return /re/`, `typeof /re/`) 뒤는 정규식이다 — 키워드도 알파벳으로 끝나
    # 직전 문자만 보면 오판한다(codex 14차).
    if prev.isalnum() or prev in "_$":
        k = j
        while k >= 0 and (source[k].isalnum() or source[k] in "_$"):
            k -= 1
        # 단어 앞이 `.` 이면 멤버 접근(프로퍼티)이라 키워드가 아니라 값 → 나눗셈.
        # `stats.default / total` 의 default 는 키워드가 아니다(codex 15차).
        before = k
        while before >= 0 and source[before] in " \t":
            before -= 1
        if before >= 0 and source[before] == ".":
            return False
        word = source[k + 1 : j + 1]
        return word in _REGEX_PREFIX_KEYWORDS  # 키워드 뒤면 정규식, 값이면 나눗셈
    return True


# 뒤에 정규식 리터럴이 올 수 있는 JS/TS 키워드·연산자 단어.
_REGEX_PREFIX_KEYWORDS = {
    "return", "typeof", "instanceof", "in", "of", "new", "delete", "void",
    "do", "else", "yield", "await", "case", "throw", "default",
}


def string_literals(source: str) -> list[tuple[int, str, int, int]]:
    """소스에서 문자열 리터럴을 (시작 줄, 내용, 시작 오프셋, 끝 오프셋)으로 뽑는다.

    줄 주석(`//`) 이후는 코드가 아니므로 무시하고, 따옴표 **안**의 `//`(URL 등)는
    주석으로 오인하지 않는다. Dart 의 `'''` 블록과 TS 의 백틱 template literal 처럼
    여러 줄에 걸친 문자열도 끝까지 따라간다 — 줄 단위로만 보면 라벨을 여러 줄 문자열
    안에 넣는 것만으로 가드를 피할 수 있었다.

    오프셋을 함께 주는 이유: 인접 문자열 연결('테' '니스')을 판정하려면 두 리터럴
    사이에 공백뿐인지 원문에서 확인해야 한다. 줄 번호만으로 묶으면 `{'테': 1, '니스': 2}`
    같은 맵 리터럴을 오탐한다.
    """
    literals: list[tuple[int, str, int, int]] = []
    index, length, line_no = 0, len(source), 1
    while index < length:
        char = source[index]
        if char == "\n":
            line_no += 1
            index += 1
            continue
        if char == "/" and index + 1 < length and source[index + 1] == "/":
            # 라인 주석. 종료는 ECMAScript 줄종료 전부다 — LF 만 보면 U+2028 로 주석을
            # 끊고 그 뒤에 라벨을 둬 우회할 수 있다(codex 13차).
            while index < length and source[index] not in "\n\r\u2028\u2029":
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
        if char == "/" and _regex_context(source, index):
            # JS/TS 정규식 리터럴 `/…/flags`. 안에 따옴표가 들어가면(`/'/`, `/['"]/`)
            # 스캐너가 그걸 문자열 시작으로 오인해, 다음 진짜 따옴표(라벨의 여는 따옴표)까지
            # 삼켜 라벨 검출이 통째로 깨진다(codex 13차). 정규식은 값 문맥이 아닌 곳에서만
            # 시작하므로 직전 유의미 문자로 보수적으로 판별한다(나눗셈과 구분).
            cursor = index + 1
            in_class = False
            closed = False
            while cursor < length:
                rc = source[cursor]
                if rc == "\\":
                    cursor += 2
                    continue
                if rc in "\n\r\u2028\u2029":
                    break  # 정규식은 줄을 넘지 않는다 — 나눗셈이었다.
                if rc == "[":
                    in_class = True
                elif rc == "]":
                    in_class = False
                elif rc == "/" and not in_class:
                    closed = True
                    break
                cursor += 1
            if closed:
                index = cursor + 1
                continue
            # 닫는 `/` 를 못 찾았으면 정규식이 아니라 나눗셈이었다 — 원위치로 진행.
        if char in "'\"`":
            # Dart raw 문자열 `r'…'` 은 백슬래시가 리터럴이라 이스케이프·보간이 없다.
            # 디코드하면 `r'테…'`(런타임 값은 문자 그대로) 를 라벨로 오탐한다(codex 10차).
            is_raw = (
                index > 0
                and source[index - 1] in "rR"
                and not (index >= 2 and (source[index - 2].isalnum() or source[index - 2] == "_"))
            )
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
                if not is_raw and current == "\\":
                    # 이스케이프를 통째로 버린 게 아니라 보존해서 나중에 디코드한다 —
                    # `'입문'`(='입문')처럼 유니코드 이스케이프로 라벨을 숨기면
                    # 그냥 건너뛸 때 검출을 통째로 피했다(codex 9차).
                    buffer.append(source[cursor : cursor + 2])
                    cursor += 2
                    continue
                # 보간 `${…}` 안은 문자열이 아니라 코드다. 통째로 리터럴 취급하면
                # `${ok ? '테니스' : '풋살'}` 처럼 감싸는 것만으로 가드를 피할 수 있다.
                # Dart 는 '…' / "…" 에도 보간이 있으므로 백틱 전용이 아니다.
                # 중괄호를 셀 때 문자열과 주석 안의 것은 빼야 한다 — `${ok ? '}' : '테니스'}`,
                # `${/* } */ ok ? '테니스' : '풋살'}` 가 식 종료를 오인시킨다.
                # raw 문자열은 `${…}` 도 리터럴이라 보간이 아니다.
                if not is_raw and source.startswith("${", cursor):
                    depth, scan, expr_line = 1, cursor + 2, line_no
                    while scan < length and depth:
                        inner_char = source[scan]
                        if inner_char in "'\"`":
                            scan += 1
                            while scan < length and source[scan] != inner_char:
                                if source[scan] == "\\":
                                    scan += 2
                                    continue
                                if source[scan] == "\n":
                                    line_no += 1
                                scan += 1
                            scan += 1
                            continue
                        if source.startswith("//", scan):
                            while scan < length and source[scan] != "\n":
                                scan += 1
                            continue
                        if source.startswith("/*", scan):
                            comment_depth, scan = 1, scan + 2
                            while scan < length and comment_depth:
                                if source.startswith("/*", scan):
                                    comment_depth += 1
                                    scan += 2
                                    continue
                                if source.startswith("*/", scan):
                                    comment_depth -= 1
                                    scan += 2
                                    continue
                                if source[scan] == "\n":
                                    line_no += 1
                                scan += 1
                            continue
                        if inner_char == "{":
                            depth += 1
                        elif inner_char == "}":
                            depth -= 1
                        elif inner_char == "\n":
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
            end = cursor + len(delim)
            content = "".join(buffer) if is_raw else decode_string_escapes("".join(buffer))
            literals.append((start_line, content, index, end))
            for expr_line, expression in embedded:
                # 보간식 안의 리터럴은 원문 오프셋을 물려주지 않는다(인접 판정 대상이 아니다).
                for inner_line, inner, _s, _e in string_literals(expression):
                    literals.append((expr_line + inner_line - 1, inner, -1, -1))
            index = end
            continue
        index += 1
    return literals


def forbidden_labels(*, grades_only: bool = False) -> set[str]:
    """정본(grade_labels.dart)의 등급·종목 라벨 + 폐기 라벨.
    grades_only=True 면 등급 라벨만 — 종목 라벨의 정본인 파일(enums.ts)을 검사할 때 쓴다."""
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
    if not grades_only:
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
    for start_line, literal, _start, _end in literals:
        for offset, piece in enumerate(literal.split("\n")):
            if piece.strip() in labels:
                found.append((start_line + offset, piece.strip()))
    # Dart 는 **인접한** 문자열을 컴파일 시 하나로 합친다('테' '니스' == '테니스').
    # 인접의 기준은 같은 줄이 아니라 "사이에 공백뿐"이다 — 줄을 나눠도 합쳐지고,
    # 반대로 `{'테': 1, '니스': 2}` 는 사이에 코드가 있어 합쳐지지 않는다.
    runs: list[list[tuple[int, str]]] = []
    previous_end = -1
    for start_line, literal, start, end in literals:
        if start < 0 or "\n" in literal:
            previous_end = -1
            continue
        # 주석은 공백과 같다 — `'테' /* gap */ '니스'` 도 Dart 가 하나로 합친다.
        gap = re.sub(r"/\*.*?\*/|//[^\n]*", "", source[previous_end:start], flags=re.S)
        if previous_end >= 0 and gap.strip() == "":
            runs[-1].append((start_line, literal))
        else:
            runs.append([(start_line, literal)])
        previous_end = end
    for run in runs:
        for start in range(len(run)):
            for end in range(start + 2, len(run) + 1):
                joined = "".join(piece for _line, piece in run[start:end]).strip()
                if joined in labels:
                    found.append((run[start][0], joined))
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
    # Dart 인접 문자열 연결은 컴파일 시 하나로 합쳐진다. 줄을 나눠도 마찬가지다.
    "const s = '테' '니스';",
    "const s = '테'\n    '니스';",
    # 보간식 안 문자열의 중괄호를 식 종료로 오인하면 나머지가 통째로 빠져나간다.
    "const z = `${ok ? '}' : '테니스'}`;",
    # 유니코드 이스케이프로 숨긴 라벨('입문' == '입문').
    "const a = '\\uc785\\ubb38';",
    "const b = '\\u{c785}\\u{bb38}';",
    # 줄 연속(백슬래시+줄종료)으로 쪼갠 라벨. TS 에서 '테\<종료>니스' == '테니스'.
    # LF·단독 CR·U+2028 모두 줄 연속이라 라벨이 하나로 합쳐진다.
    "const c = '테\\\n니스';",
    "const d = '테\\\r니스';",
    "const e = '테\\ 니스';",
    # Dart 는 작은/큰따옴표 문자열에도 보간이 있다 — 백틱 전용으로 보면 놓친다.
    "final s = \"${ok ? '테니스' : '풋살'}\";",
    # 보간식 안 주석의 중괄호도 식 종료로 오인하면 안 된다.
    "const w = `${/* } */ ok ? '테니스' : '풋살'}`;",
    # 인접 판정에서 주석은 공백이다.
    "const c = '테' /* gap */ '니스';",
    # JS/TS 정규식 리터럴(따옴표 포함)로 스캐너를 헷갈리게 한 뒤 하드코딩한 라벨(codex 13차).
    "const rx = /'/.test(s); const label = '테니스';",
    # 공백 든 정규식이 조기 종료돼 나눗셈으로 오판되면 뒤 라벨을 놓친다(codex 14차).
    "const ry = /a b/.test(s); const label = '테니스';",
    # 키워드(return) 뒤 정규식을 나눗셈으로 오판하면 뒤 라벨을 놓친다(codex 14차).
    "function f(){ return /'/.test(x); } const l = '입문';",
    # 라인 주석을 U+2028 로 끊고 그 뒤에 둔 라벨(codex 13차 low).
    "// c\u2028const label = '입문';",
    # 멤버 접근(.default) 뒤 나눗셈을 정규식으로 오판하면 뒤 라벨을 놓친다(codex 15차).
    "const label = stats.default / stats.total > 0.5 ? '테니스' : x;",
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
    # 사이에 코드가 있으면 인접이 아니다 — 합쳐서 검사하면 맵 리터럴을 오탐한다.
    "const m = {'테': 1, '니스': 2};",
    "const pair = ['테', '니스'];",
    # raw 문자열은 유니코드 이스케이프가 리터럴이라 런타임 값이 라벨이 아니다.
    "const r = r'\\ud14c\\ub2c8\\uc2a4';",
    # 나눗셈은 정규식이 아니다 — 식별자·숫자·괄호 뒤 `/` 를 정규식으로 오인하면 안 된다.
    "const ratio = width / height; log('경기 비율');",
    "const q = (a + b) / c; log('점수');",
    # 키워드 뒤 정규식이지만 라벨이 없으면(입력 매칭용) 통과한다.
    "const ok = typeof x; if (/(테니스|tennis)/i.test(t)) return 'tennis';",
]


def check_sport_grade_label_hardcode() -> None:
    labels = forbidden_labels()
    grade_labels = forbidden_labels(grades_only=True)

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
            scan_labels = grade_labels if relative in LABEL_GRADE_ONLY_FILES else labels
            source = path.read_text(encoding="utf-8")
            lines = source.splitlines()
            for line_number, literal in label_violations(source, scan_labels):
                context = lines[line_number - 1].strip() if line_number <= len(lines) else ""
                violations.append(f"{relative}:{line_number}: '{literal}' — {context}")
    if violations:
        fail(
            "라벨 재하드코딩(JY-146): 종목·등급 라벨을 코드에 직접 적었다.\n"
            "Dart 는 sportLabel*/gradeLabel/anyGradeLabel, TS 는 SPORT_LABELS 를 쓴다.\n"
            "등급 라벨은 TS 사본이 없다(#319) — DB grades.label_ko 를 조회·임베드해 쓸 것.\n"
            + "\n".join(violations)
        )
    print(f"✓ 종목·등급 라벨이 정본 파일에서만 정의된다 (금지 라벨 {len(labels)}개, 자가검증 통과)")


def main() -> int:
    check_root_file_lengths()
    check_required_rule_docs()
    check_agents_rule_links()
    check_github_templates()
    check_no_shell_background_wrappers_in_harness()
    check_tournament_closed_is_automation_only()
    check_pureform_literal_contracts()
    check_sport_grade_label_hardcode()
    print("✅ static repository rules passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
