#!/usr/bin/env python3
"""등급 정본(public.grades) ↔ 클라이언트 폴백 상수의 일치를 **실제 DB 로** 강제한다.

왜 DB 대조인가:
    예전엔 check_enums.py 가 마이그레이션 SQL 을 정규식으로 파싱해 seed 를 재구성했다.
    그러나 유효한 PostgreSQL 문법(E-string·dollar-quote·다중 대상 TRUNCATE·CTE·quoted
    identifier·동적 EXECUTE)으로 grades 쓰기를 숨기면 파서가 놓쳤다 — codex 적대 리뷰
    5~11차에 걸쳐 fail-open 우회가 반복 발견됐다. 정규식으로 SQL 을 완전히 파싱하는 건
    원리적으로 불가능하다.

    그래서 파싱을 버리고, 마이그레이션을 **실제로 적용한 DB** 의 grades 를 직접 읽어
    폴백과 대조한다. 어떤 문법으로 썼든 최종 상태가 그대로 보이므로 우회가 불가능하다(JY-321).

전제: `supabase db reset`(또는 CI 의 `supabase start`)로 마이그레이션이 이미 적용됐다.
DB 접속은 $DATABASE_URL, 없으면 로컬 기본값.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

# check_enums 의 순수 파서(Dart/TS 상수 추출)를 재사용한다 — grades 파싱과 무관하다.
sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_enums as ce  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
DART = ROOT / "app/lib/utils/grade_labels.dart"
TS = ROOT / "supabase/functions/_shared/enums.ts"

DEFAULT_DB_URL = "postgresql://postgres:postgres@127.0.0.1:54322/postgres"


def read_grades() -> list[tuple[str, str, str, bool]]:
    """DB 에서 (sport, code, label_ko, is_active) 를 sort_order 순으로 읽는다.

    JSON 으로 받는다 — TSV 는 label_ko(무제약 text)에 탭·개행이 들어가면 컬럼 경계가
    깨져, 조작된 라벨이 논리 행 수를 늘려 false-pass 를 만든다(codex 12차). psql 이
    json_agg 로 출력하면 값의 특수문자가 이스케이프되므로 이 우회가 불가능하다.
    정렬 tie-break 로 code 를 넣어(sort_order 는 non-unique) 결과가 결정적이게 한다.
    """
    db_url = os.environ.get("DATABASE_URL", DEFAULT_DB_URL)
    query = (
        "select coalesce(json_agg(json_build_object("
        "'sport', sport, 'code', code, 'label', label_ko, 'active', is_active) "
        "order by sport, sort_order, code), '[]') from public.grades"
    )
    try:
        out = subprocess.run(
            ["psql", db_url, "-tAc", query],
            capture_output=True, text=True, check=True,
        ).stdout
    except FileNotFoundError:
        raise AssertionError("psql 이 PATH 에 없다 — DB 대조를 실행할 수 없다")
    except subprocess.CalledProcessError as exc:
        raise AssertionError(f"grades 조회 실패: {exc.stderr.strip()}")

    try:
        data = json.loads(out)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"grades JSON 파싱 실패: {exc} — 원문 {out[:200]!r}")

    rows = [(r["sport"], r["code"], r["label"], r["active"]) for r in data]
    if not rows:
        raise AssertionError("public.grades 가 비어 있다 — 마이그레이션이 적용됐는지 확인하라")
    return rows


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
    rows = read_grades()
    dart = ce.read(DART)
    ts = ce.read(TS)

    # 선택지 코드는 활성 등급만(폴백 목록과 대응). 순서는 sort_order(쿼리)가 정한다.
    def active_codes(sport: str) -> list[str]:
        return [code for s, code, _label, active in rows if s == sport and active]

    # 라벨은 폐기 등급까지(과거 데이터 표시). 표기는 'code=label'.
    label_entries = sorted(f"{code}={label}" for _s, code, label, _a in rows)

    assert_same(
        "grade labels",
        ("DB public.grades", label_entries),
        ("Dart 폴백 gradeLabels", sorted(ce.dart_const_map(dart, "_kFallbackGradeLabels"))),
        ("TypeScript GRADE_LABELS", sorted(ce.ts_record(ts, "GRADE_LABELS"))),
    )
    assert_same(
        "tennis grades",
        ("DB public.grades (tennis)", active_codes("tennis")),
        ("Dart 폴백 tennisGrades", ce.dart_const_list(dart, "_kFallbackTennisGrades")),
        ("TypeScript TENNIS_GRADES", ce.ts_const_array(ts, "TENNIS_GRADES")),
    )
    assert_same(
        "futsal grades",
        ("DB public.grades (futsal)", active_codes("futsal")),
        ("Dart 폴백 futsalGrades", ce.dart_const_list(dart, "_kFallbackFutsalGrades")),
        ("TypeScript FUTSAL_GRADES", ce.ts_const_array(ts, "FUTSAL_GRADES")),
    )
    # code 는 종목을 가로질러 유일해야 한다(앱 라벨 맵이 code 단일 키). DB 제약이 이미
    # 막지만(grades_code_unique), 게이트에서도 확인해 회귀를 조기에 잡는다.
    seen: dict[str, str] = {}
    for sport, code, _label, _a in rows:
        if code in seen and seen[code] != sport:
            raise AssertionError(
                f"grades: code '{code}' 가 {seen[code]}·{sport} 두 종목에 있다"
            )
        seen[code] = sport
    print("✓ grade code 종목 간 유일성")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"❌ grades parity failed:\n{exc}", file=sys.stderr)
        raise SystemExit(1)
