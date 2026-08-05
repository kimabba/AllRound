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

# Flutter SDK 가 `sdk: flutter` 로 넣어주는 것들 — pub 에서 받는 부품이 아니라 대장 대상이 아니다.
SDK_PACKAGES = {"flutter", "flutter_localizations", "flutter_test", "integration_test"}

# 검사할 블록. dev_dependencies 도 본다 —
# "dev 는 앱에 안 들어간다"는 전제는 사실이 아니다. 실제로 `integration_test`(dev)가
# app/ios/Runner/GeneratedPluginRegistrant.m 에 네이티브 플러그인으로 등록돼 있다
# (2026-08-04 실측). dev 쪽에 플러그인을 넣어 대장을 우회할 수 있으므로 같이 본다.
DEPENDENCY_BLOCKS = ("dependencies", "dev_dependencies")

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
    """pubspec.yaml 의 dependencies · dev_dependencies 에서 부품 이름을 뽑는다.

    dart pub 이 쓰는 2칸 들여쓰기를 전제한다. 그 밖의 유효한 YAML 문법
    (따옴표 키 `"pkg":`, 명시적 키 `? pkg` / `: ^1.0`)은 이름 대조를 우회하므로,
    **못 읽는 줄이 하나라도 있으면 통과시키지 않고 실패**시켜 사람이 보게 한다.
    주석과 빈 줄, 하위 속성(4칸 이상)은 정상적으로 건너뛴다.
    """
    text = read(PUBSPEC)
    # 따옴표(큰/작은)를 씌워도 유효한 YAML 이라 둘 다 허용한다.
    if re.search(r"""^['"]?dependency_overrides['"]?:""", text, flags=re.MULTILINE):
        fail(
            "app/pubspec.yaml 에 dependency_overrides 가 있다. 같은 이름으로 다른 구현(git/path)을 "
            "끼워 넣을 수 있어 이름 대조가 무의미해진다 — 왜 필요한지 대장에 적고 이 검사를 손볼 것."
        )
    if (ROOT / "app" / "pubspec_overrides.yaml").is_file():
        fail("app/pubspec_overrides.yaml 이 있다 — dependency_overrides 와 같은 이유로 확인이 필요하다.")

    names: list[str] = []
    for block_name in DEPENDENCY_BLOCKS:
        match = re.search(
            rf"""^['"]?{block_name}['"]?:[^\n]*\n(.*?)^(?:['"]?[a-zA-Z_][a-zA-Z0-9_]*['"]?:|\Z)""",
            text,
            flags=re.MULTILINE | re.DOTALL,
        )
        if not match:
            fail(f"app/pubspec.yaml 에서 {block_name} 블록을 찾지 못했다 — 형식이 바뀌었는지 확인할 것")

        for raw_line in match.group(1).splitlines():
            line = raw_line.split("#", 1)[0].rstrip()  # 주석은 정상 — 떼고 본다
            if not line.strip():
                continue
            if line.startswith("    "):  # 하위 속성(sdk:, git:, path: …)
                continue
            entry = re.match(r"^  ([a-z0-9_]+):", line)
            if not entry:
                fail(
                    f"app/pubspec.yaml {block_name} 에 이 검사가 못 읽는 줄이 있다:\n"
                    f"  {raw_line!r}\n\n"
                    "따옴표 키나 명시적 키(? …) 같은 형식은 이름 대조를 조용히 우회한다. "
                    "dart pub 이 쓰는 `  패키지명: ^버전` 형태로 맞추거나, 정말 필요하면 이 검사를 함께 고칠 것."
                )
            name = entry.group(1)
            if name not in SDK_PACKAGES:
                names.append(name)
    return sorted(set(names))


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
