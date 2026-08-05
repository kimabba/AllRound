#!/usr/bin/env python3
"""app/pubspec.yaml 의 부품과 docs/team/dependencies.md 대장이 일치하는지 검사한다.

왜 필요한가:
    2026-08-04 하루에 네이티브 부품이 둘 늘었는데(webview_flutter·cupertino_http)
    둘 다 **우연히** 발견됐다. 하나는 무관한 PR 에 섞여 들어왔고, 다른 하나는
    Commander 가 "새 PR 없냐"고 물어서 알았다. 그때 아무 기록도 남지 않았다.

    그래서 "부품을 넣으면 대장에 한 줄 적어야 CI 가 통과"하게 만든다. 그 한 줄이
    곧 기록이다 — 사람이 기억할 필요가 없다.

**이 검사가 하는 일은 하나뿐이다: 이름 대조.**
    `pubspec.yaml` 의 직접 의존성과 대장 표의 이름이 같은지만 본다. CI 러너에는
    Python 만 있고 Flutter·pub cache 가 없어서(harness.yml `repository-rules`)
    패키지 내용을 볼 수 없기 때문이다.

    대장의 **`네이티브` 열은 사람이 적는 값이고 이 검사는 그것을 검증하지 않는다.**
    검증하는 척하면 "막고 있다"는 착각만 남는다(2026-08-04 codex 리뷰 BLOCKER).
    판정을 돕고 싶으면 pub cache 가 있는 로컬에서 `--classify` 로 따로 돌린다.

`--classify` 의 한계 (돌리기 전에 알아둘 것):
    - 전이 의존성을 훑지만, 어떤 직접 부품이 그걸 데려왔는지는 알려주지 않는다.
    - FFI 패키지 중 `ffigen.yaml`·`hook/` 없이 `dart:ffi` 만 쓰는 것은 놓친다.
    - `flutter.plugin` 이면 지원 플랫폼을 따지지 않고 네이티브로 본다(웹 전용 포함).
    결국 **사람이 확인해야 한다.** 이건 출발점을 주는 도구다.
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PUBSPEC = ROOT / "app" / "pubspec.yaml"
LOCK = ROOT / "app" / "pubspec.lock"
LEDGER = ROOT / "docs" / "team" / "dependencies.md"
CACHE = Path(os.path.expanduser(os.environ.get("PUB_CACHE", "~/.pub-cache"))) / "hosted" / "pub.dev"

# Flutter SDK 가 넣어주는 것들 — 대장에 적을 대상이 아니다.
SDK_PACKAGES = {"flutter", "flutter_localizations", "flutter_test", "flutter_lints"}

# 대장에서 부품 표만 읽기 위한 구분자. 이 사이의 표만 본다 —
# 없으면 문서 아무 데나(코드 블록·주석 포함) 표 한 줄을 넣어 우회할 수 있다.
LEDGER_BEGIN = "<!-- deps:begin -->"
LEDGER_END = "<!-- deps:end -->"


def fail(message: str) -> None:
    print(f"❌ {message}")
    raise SystemExit(1)


def read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        fail(f"{path.relative_to(ROOT)} 를 찾을 수 없다")
        raise  # unreachable


def declared_dependencies() -> list[str]:
    """pubspec.yaml 의 dependencies 블록에서 직접 의존성 이름만 뽑는다.

    dart pub 이 쓰는 2칸 들여쓰기를 전제한다. 다른 들여쓰기나 따옴표 키는
    이 검사가 못 보므로, 형식이 어긋나면 통과시키지 않고 실패시킨다.
    """
    text = read(PUBSPEC)
    if re.search(r"^dependency_overrides:", text, flags=re.MULTILINE):
        fail(
            "app/pubspec.yaml 에 dependency_overrides 가 있다. 같은 이름으로 다른 구현(git/path)을 "
            "끼워 넣을 수 있어 이름 대조가 무의미해진다 — 왜 필요한지 대장에 적고 이 검사를 손볼 것."
        )
    if (ROOT / "app" / "pubspec_overrides.yaml").is_file():
        fail("app/pubspec_overrides.yaml 이 있다 — dependency_overrides 와 같은 이유로 확인이 필요하다.")

    match = re.search(
        r"^dependencies:[^\n]*\n(.*?)^(?:[a-z_]+:|\Z)",
        text,
        flags=re.MULTILINE | re.DOTALL,
    )
    if not match:
        fail("app/pubspec.yaml 에서 dependencies 블록을 찾지 못했다 — 형식이 바뀌었는지 확인할 것")
    block = match.group(1)

    # 2칸 들여쓰기 + 따옴표 없는 키만 인식한다. 그 밖의 항목이 있으면 조용히
    # 넘기지 않고 사람에게 보인다.
    entries = re.findall(r"^  (\S[^:\n]*):", block, flags=re.MULTILINE)
    names = []
    for raw in entries:
        if not re.fullmatch(r"[a-z0-9_]+", raw):
            fail(
                f"app/pubspec.yaml dependencies 에 이 검사가 못 읽는 항목이 있다: {raw!r}\n"
                "따옴표 키나 특이한 형식은 이름 대조를 우회한다 — 형식을 맞추거나 검사를 고칠 것."
            )
        if raw not in SDK_PACKAGES:
            names.append(raw)
    return sorted(names)


def ledger_entries() -> set[str]:
    """대장의 부품 표(구분자 사이)에서 첫 칸의 이름만 읽는다."""
    text = read(LEDGER)
    if LEDGER_BEGIN not in text or LEDGER_END not in text:
        fail(
            f"docs/team/dependencies.md 에 {LEDGER_BEGIN} / {LEDGER_END} 구분자가 없다.\n"
            "이 구분자 사이의 표만 대장으로 인정한다 — 없으면 문서 아무 데나 한 줄 넣어 우회할 수 있다."
        )
    table = text.split(LEDGER_BEGIN, 1)[1].split(LEDGER_END, 1)[0]
    return set(re.findall(r"^\|\s*`([a-z0-9_]+)`\s*\|", table, flags=re.MULTILINE))


def locked_versions() -> dict[str, str]:
    if not LOCK.is_file():
        return {}
    versions: dict[str, str] = {}
    current: str | None = None
    for line in LOCK.read_text(encoding="utf-8").splitlines():
        name = re.match(r"^  ([a-z0-9_]+):\s*$", line)
        if name:
            current = name.group(1)
            continue
        version = re.match(r'^    version:\s*"?([^"\s]+)"?\s*$', line)
        if version and current:
            versions[current] = version.group(1)
            current = None
    return versions


def looks_native(name: str, version: str) -> bool | None:
    """설치된 패키지가 네이티브인지 추정한다. pub cache 가 없으면 None.

    폴더 이름(ios/·android/)으로 보면 틀린다 — 2026-08-04 실측: `image` 는 순수
    Dart 인데 `image_picker_ios` 때문에 네이티브로 잡혔고, `cupertino_http` 는
    FFI 라 플랫폼 폴더가 없는데도 애플 프레임워크를 직접 부른다.
    """
    directory = CACHE / f"{name}-{version}"
    manifest = directory / "pubspec.yaml"
    if not manifest.is_file():
        return None
    text = manifest.read_text(encoding="utf-8")
    flutter_block = re.search(r"^flutter:\s*$(.*?)(?=^\S|\Z)", text, flags=re.MULTILINE | re.DOTALL)
    if flutter_block and re.search(r"^  plugin:\s*$", flutter_block.group(1), flags=re.MULTILINE):
        return True
    return (directory / "ffigen.yaml").is_file() or (directory / "hook").is_dir()


def classify_report() -> int:
    """로컬 보조 도구: 전이 의존성까지 훑어 네이티브 후보를 보여준다."""
    versions = locked_versions()
    if not versions:
        fail("app/pubspec.lock 이 없다 — flutter pub get 을 먼저 돌릴 것")
    direct = set(declared_dependencies())
    unknown = 0
    native_direct, native_transitive, pure = [], [], []
    for name, version in sorted(versions.items()):
        verdict = looks_native(name, version)
        if verdict is None:
            unknown += 1
            continue
        if verdict:
            (native_direct if name in direct else native_transitive).append(name)
        elif name in direct:
            pure.append(name)

    print(f"직접 부품 {len(direct)}개 · lock 전체 {len(versions)}개")
    print(f"\n[네이티브 · 직접] {len(native_direct)}개\n  " + ", ".join(native_direct))
    print(f"\n[네이티브 · 전이(다른 부품이 데려옴)] {len(native_transitive)}개\n  " + ", ".join(native_transitive))
    print(f"\n[순수 Dart · 직접] {len(pure)}개\n  " + ", ".join(pure))
    if unknown:
        print(f"\n판정 불가 {unknown}개 (pub cache 에 없음 — git/path 의존성이거나 pub get 필요)")
    print(
        "\n⚠️ 전이 목록은 '어떤 직접 부품이 데려왔는지'까지 알려주지 않는다. "
        "순수 Dart 로 분류된 직접 부품도 네이티브를 데려올 수 있다"
        "(실제 예: supabase_flutter → app_links). 최종 판단은 사람이 한다."
    )
    return 0


def main() -> int:
    if "--classify" in sys.argv:
        return classify_report()

    declared = declared_dependencies()
    recorded = ledger_entries()

    missing = [name for name in declared if name not in recorded]
    if missing:
        fail(
            "app/pubspec.yaml 에 있는데 docs/team/dependencies.md 대장에 없는 부품:\n  "
            + "\n  ".join(missing)
            + "\n\n부품이 조용히 늘어나는 걸 막는 검사다. 대장에 한 줄 적으면 통과한다 "
            "— 무엇에 쓰는지, 왜 넣었는지, 네이티브인지, 아이폰에서 확인했는지.\n"
            "네이티브인지 모르겠으면: python3 scripts/harness/check_dependencies.py --classify"
        )

    extra = sorted(name for name in recorded if name not in declared)
    if extra:
        fail(
            "대장에는 있는데 app/pubspec.yaml 에서 사라진 부품: "
            + ", ".join(extra)
            + "\n뺐으면 대장에서도 지울 것."
        )

    print(f"✓ 직접 부품 {len(declared)}개가 전부 대장에 있다 (네이티브 여부는 사람이 적는 값 — 검증하지 않음)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
