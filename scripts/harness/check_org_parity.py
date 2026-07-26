#!/usr/bin/env python3
"""협회 정본(public.tennis_orgs) ↔ 클라이언트 폴백 상수의 일치를 **실제 DB 로** 강제한다.

왜 DB 대조인가:
    JY-135(#331)에서 협회 목록·라벨 정본을 Dart 하드코딩에서 DB tennis_orgs 로 옮기며
    check_enums.py 의 협회 3층 비교(이미 삭제된 SQL enum 텍스트가 대상이던 죽은 검사)를
    없앴다. 그 결과 앱 폴백 상수(OrgCatalog 미로드 시 쓰는 오프라인 값)가 DB 와 어긋나도
    아무도 못 잡는 공백이 생겼다(#330). check_grades_parity.py(JY-321)와 같은 이유로,
    마이그레이션 SQL 을 정규식으로 재구성하지 않고 **적용된 DB** 를 직접 읽어 대조한다.

전제: `supabase db reset`(또는 CI 의 `supabase start`)로 마이그레이션이 이미 적용됐다.
DB 접속은 $DATABASE_URL, 없으면 로컬 기본값.
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DART = ROOT / "app/lib/utils/grade_labels.dart"

DEFAULT_DB_URL = "postgresql://postgres:postgres@127.0.0.1:54322/postgres"


def read(path: Path) -> str:
    if not path.exists():
        raise AssertionError(f"missing required file: {path.relative_to(ROOT)}")
    return path.read_text(encoding="utf-8")


def read_orgs() -> list[dict]:
    """DB 에서 (code, label, short_label, active) 를 sort_order, name_ko, code 순으로 읽는다.

    label_ko/short_label 이 null 이면 각각 name_ko/label 로 폴백한다 — 앱
    OrgCatalog.ingestRows(grade_labels.dart)의 규칙을 SQL 에서 그대로 재현한다.

    JSON 으로 받는 이유는 check_grades_parity.py 와 같다: 라벨에 괄호·쉼표·가운뎃점이
    들어 있어(예: '한국시니어테니스연맹 (KSTF, 60+)') TSV 로 받으면 탭·개행 주입으로
    컬럼 경계가 깨질 위험이 있다(codex 12차 선례). json_agg 는 특수문자를 이스케이프한다.
    """
    db_url = os.environ.get("DATABASE_URL", DEFAULT_DB_URL)
    query = (
        "select coalesce(json_agg(json_build_object("
        "'code', code, "
        "'label', coalesce(label_ko, name_ko), "
        "'short_label', coalesce(short_label, coalesce(label_ko, name_ko)), "
        "'active', is_active) "
        "order by sort_order, name_ko, code), '[]') from public.tennis_orgs"
    )
    try:
        out = subprocess.run(
            ["psql", db_url, "-tAc", query],
            capture_output=True, text=True, check=True,
        ).stdout
    except FileNotFoundError:
        raise AssertionError("psql 이 PATH 에 없다 — DB 대조를 실행할 수 없다")
    except subprocess.CalledProcessError as exc:
        raise AssertionError(f"tennis_orgs 조회 실패: {exc.stderr.strip()}")

    try:
        data = json.loads(out)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"tennis_orgs JSON 파싱 실패: {exc} — 원문 {out[:200]!r}")

    if not data:
        raise AssertionError("public.tennis_orgs 가 비어 있다 — 마이그레이션이 적용됐는지 확인하라")
    return data


# 이름 있는 인자(code:/label:/shortLabel:/isActive:)를 순서대로 뽑는다. 라벨에
# 괄호·쉼표가 있어(예: '(KSTF, 60+)') 항목 경계를 괄호 매칭으로 잡으면 깨진다 —
# 따옴표로 감싼 값은 괄호 개수와 무관하게 다음 홑따옴표에서 끝나므로 이 방식이 안전하다.
_ENTRY_RE = re.compile(
    r"TennisOrgEntry\(\s*"
    r"code:\s*'([^']*)'\s*,\s*"
    r"label:\s*'([^']*)'\s*,\s*"
    r"shortLabel:\s*'([^']*)'\s*,\s*"
    r"isActive:\s*(true|false)\s*"
    r"\)",
)


def read_dart_fallback(text: str) -> list[dict]:
    block_match = re.search(
        r"const\s+_kFallbackOrgEntries\s*=\s*<TennisOrgEntry>\s*\[(.*?)\];",
        text, re.S,
    )
    if not block_match:
        raise AssertionError("Dart _kFallbackOrgEntries 를 찾지 못했다")
    entries = [
        {
            "code": m.group(1),
            "label": m.group(2),
            "short_label": m.group(3),
            "active": m.group(4) == "true",
        }
        for m in _ENTRY_RE.finditer(block_match.group(1))
    ]
    if not entries:
        raise AssertionError("Dart _kFallbackOrgEntries 항목을 하나도 파싱하지 못했다")
    return entries


def as_rows(entries: list[dict]) -> list[tuple]:
    return [(e["code"], e["label"], e["short_label"], e["active"]) for e in entries]


def main() -> int:
    db_rows = as_rows(read_orgs())
    dart_rows = as_rows(read_dart_fallback(read(DART)))

    if db_rows != dart_rows:
        lines = [
            f"DB public.tennis_orgs 항목 수: {len(db_rows)}, Dart 폴백 항목 수: {len(dart_rows)}",
        ]
        for i, (db_row, dart_row) in enumerate(zip(db_rows, dart_rows)):
            if db_row != dart_row:
                lines.append(f"  [{i}] DB={db_row}\n      Dart={dart_row}")
        if len(db_rows) != len(dart_rows):
            shorter = min(len(db_rows), len(dart_rows))
            tail_name, tail = (
                ("DB", db_rows[shorter:])
                if len(db_rows) > len(dart_rows)
                else ("Dart", dart_rows[shorter:])
            )
            lines.append(f"  {tail_name} 에만 있는 꼬리: {tail}")
        raise AssertionError("\n".join(lines))

    print(f"✓ tennis org catalog ({len(db_rows)}개 일치, 순서: sort_order, name_ko, code)")
    for code, label, short_label, active in db_rows:
        print(f"  {code}: {label!r} / {short_label!r} / active={active}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"❌ org parity failed:\n{exc}", file=sys.stderr)
        raise SystemExit(1)
