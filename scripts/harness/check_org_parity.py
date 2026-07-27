#!/usr/bin/env python3
"""협회 정본(public.tennis_orgs) ↔ 클라이언트 폴백 스냅샷의 일치를 **실제 DB 로** 강제한다.

왜 DB 대조인가:
    JY-135(#331)에서 협회 목록·라벨 정본을 Dart 하드코딩에서 DB tennis_orgs 로 옮기며
    check_enums.py 의 협회 3층 비교(이미 삭제된 SQL enum 텍스트가 대상이던 죽은 검사)를
    없앴다. 그 결과 앱 폴백 상수가 DB 와 어긋나도 아무도 못 잡는 공백이 생겼다(#330).

왜 Dart 소스를 정규식으로 읽지 않는가:
    처음엔 grade_labels.dart 를 정규식으로 파싱했다. codex 가 두 라운드에 걸쳐 사각지대
    (줄 주석, 블록 주석, 이스케이프 시퀀스, 공백 변형)를 계속 찾아냈다 — JY-146 에서 이미
    같은 결론에 도달한 문제다(#322): "소스 대상 검사는 실제 파서가 근본이다." 정규식
    패치를 반복해도 문법 사각지대는 끝이 없다.

    그래서 Dart 파싱을 완전히 버리고 **스냅샷 다리**를 둔다:
      DB ──(이 스크립트)──▶ app/test/fixtures/org_fallback.json ◀──(Flutter 테스트)── Dart 폴백
    Flutter 테스트(app/test/grade_labels_test.dart)가 OrgCatalog.instance.all(미로드 상태,
    즉 실제 폴백)을 이 JSON 스냅샷과 비교한다 — 진짜 Dart 코드가 만든 값이라 문법 사각지대가
    원천적으로 없다. 이 스크립트는 같은 스냅샷을 DB 와 비교한다. 둘 중 하나만 어긋나도
    한쪽 잡이 반드시 빨간불이 된다.

전제: `supabase db reset`(또는 CI 의 `supabase start`)로 마이그레이션이 이미 적용됐다.
DB 접속은 $DATABASE_URL, 없으면 로컬 기본값.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SNAPSHOT = ROOT / "app/test/fixtures/org_fallback.json"

DEFAULT_DB_URL = "postgresql://postgres:postgres@127.0.0.1:54322/postgres"


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
        "'shortLabel', coalesce(short_label, coalesce(label_ko, name_ko)), "
        "'isActive', is_active) "
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


def read_snapshot() -> list[dict]:
    if not SNAPSHOT.exists():
        raise AssertionError(f"missing required file: {SNAPSHOT.relative_to(ROOT)}")
    try:
        data = json.loads(SNAPSHOT.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise AssertionError(f"{SNAPSHOT.relative_to(ROOT)} JSON 파싱 실패: {exc}")
    if not data:
        raise AssertionError(f"{SNAPSHOT.relative_to(ROOT)} 가 비어 있다")
    return data


def as_rows(entries: list[dict]) -> list[tuple]:
    return [
        (e["code"], e["label"], e["shortLabel"], e["isActive"]) for e in entries
    ]


def main() -> int:
    db_rows = as_rows(read_orgs())
    snapshot_rows = as_rows(read_snapshot())

    if db_rows != snapshot_rows:
        lines = [
            f"DB public.tennis_orgs 항목 수: {len(db_rows)}, "
            f"스냅샷 항목 수: {len(snapshot_rows)} "
            f"({SNAPSHOT.relative_to(ROOT)})",
        ]
        for i, (db_row, snap_row) in enumerate(zip(db_rows, snapshot_rows)):
            if db_row != snap_row:
                lines.append(f"  [{i}] DB={db_row}\n      snapshot={snap_row}")
        if len(db_rows) != len(snapshot_rows):
            shorter = min(len(db_rows), len(snapshot_rows))
            tail_name, tail = (
                ("DB", db_rows[shorter:])
                if len(db_rows) > len(snapshot_rows)
                else ("snapshot", snapshot_rows[shorter:])
            )
            lines.append(f"  {tail_name} 에만 있는 꼬리: {tail}")
        lines.append(
            "  ※ 폴백(Dart)이 스냅샷과 일치하는지는 `flutter test` 의 "
            "OrgCatalog 스냅샷 테스트가 따로 검증한다."
        )
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
