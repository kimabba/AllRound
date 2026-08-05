#!/usr/bin/env python3
"""app/pubspec.yaml 의 부품과 docs/team/dependencies.md 대장이 일치하는지 검사한다.

왜 필요한가:
    2026-08-04 하루에 네이티브 부품이 둘 늘었는데(webview_flutter·cupertino_http)
    둘 다 **우연히** 발견됐다. 하나는 무관한 PR 에 섞여 들어왔고, 다른 하나는
    Commander 가 "새 PR 없냐"고 물어서 알았다. 그때 아무 기록도 남지 않았다.

    네이티브 부품은 "안드로이드에서 잘 되네"가 증거가 되지 않는다 — iOS 는 기본
    동작이 다르고(권한 프롬프트 등) 실기기에서만 터지는 문제가 있다. 앱이 이미
    스토어에 있으므로 새 부품은 기존 사용자 전원에게 나간다.

    그래서 "부품을 넣으면 대장에 한 줄 적어야 CI 가 통과"하게 만든다. 그 한 줄이
    곧 기록이다 — 사람이 기억할 필요가 없다.

의존성 없이 돈다:
    CI 러너에 PyYAML 이 없다(2026-08-04 실측 실패). 다른 하네스 스크립트처럼
    표준 라이브러리 정규식만 쓴다. pubspec 의 dependencies 는 2칸 들여쓰기 한
    단순 구조라 이걸로 충분하다.

한계:
    대장에 이름만 적으면 통과한다. "왜 넣었나"가 성의 없이 적히는 것까지는 막지
    못한다. 이 검사의 몫은 **부품이 조용히 늘어나는 것**을 막는 데까지다.
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
CACHE = Path(os.path.expanduser("~/.pub-cache/hosted/pub.dev"))

# Flutter SDK 가 넣어주는 것들 — 대장에 적을 대상이 아니다.
SDK_PACKAGES = {"flutter", "flutter_localizations", "flutter_test", "flutter_lints"}


def fail(message: str) -> None:
    print(f"❌ {message}")
    raise SystemExit(1)


def read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        fail(f"{path.relative_to(ROOT)} 를 찾을 수 없다")
        raise  # unreachable, satisfies type checkers


def declared_dependencies() -> list[str]:
    """pubspec.yaml 의 dependencies 블록에서 최상위 부품 이름만 뽑는다."""
    text = read(PUBSPEC)
    match = re.search(
        r"^dependencies:\s*$(.*?)^(?:dev_dependencies|dependency_overrides|flutter):",
        text,
        flags=re.MULTILINE | re.DOTALL,
    )
    if not match:
        fail("app/pubspec.yaml 에서 dependencies 블록을 찾지 못했다 — 형식이 바뀌었는지 확인할 것")
    names = re.findall(r"^  ([a-z0-9_]+):", match.group(1), flags=re.MULTILINE)
    return sorted(n for n in names if n not in SDK_PACKAGES)


def locked_versions() -> dict[str, str]:
    """pubspec.lock 에서 패키지별 확정 버전을 읽는다(네이티브 판정용)."""
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


def ledger_entries() -> set[str]:
    """대장 표의 첫 칸(`백틱으로 감싼 부품명`)만 읽는다."""
    return set(re.findall(r"^\|\s*`([a-z0-9_]+)`\s*\|", read(LEDGER), flags=re.MULTILINE))


def classify(name: str, version: str) -> str:
    """설치된 패키지를 보고 네이티브인지 판정한다.

    폴더 이름(ios/·android/)으로 보면 틀린다 — 2026-08-04 실측: `image` 는 순수
    Dart 인데 `image_picker_ios` 때문에 네이티브로 잡혔고, `cupertino_http` 는
    FFI 라 플랫폼 폴더가 없는데도 실제로는 애플 프레임워크를 직접 부른다.
    패키지가 스스로 선언한 값을 본다.

    pub cache 가 없으면(clean CI 등) '확인불가'. 이 검사의 본래 목적은
    '대장에 적혔는가'이고, 네이티브 판정은 사람을 돕는 부가 정보다.
    """
    directory = CACHE / f"{name}-{version}"
    manifest = directory / "pubspec.yaml"
    if not manifest.is_file():
        return "확인불가"
    text = manifest.read_text(encoding="utf-8")
    # flutter: 밑에 plugin: 이 있으면 플랫폼별 네이티브 코드를 가진 플러그인이다.
    flutter_block = re.search(
        r"^flutter:\s*$(.*?)(?=^\S|\Z)", text, flags=re.MULTILINE | re.DOTALL
    )
    if flutter_block and re.search(r"^  plugin:\s*$", flutter_block.group(1), flags=re.MULTILINE):
        return "네이티브"
    if (directory / "ffigen.yaml").is_file() or (directory / "hook").is_dir():
        return "네이티브"
    return "순수 Dart"


def main() -> int:
    declared = declared_dependencies()
    recorded = ledger_entries()
    versions = locked_versions()

    missing = [name for name in declared if name not in recorded]
    if missing:
        lines = []
        for name in missing:
            kind = classify(name, versions.get(name, ""))
            mark = " ← **네이티브. 아이폰 실기기 확인이 필요하다**" if kind == "네이티브" else ""
            lines.append(f"  - {name} ({kind}){mark}")
        fail(
            "app/pubspec.yaml 에 있는데 docs/team/dependencies.md 대장에 없는 부품:\n"
            + "\n".join(lines)
            + "\n\n부품이 조용히 늘어나는 걸 막는 검사다. 대장에 한 줄 적으면 통과한다 "
            "— 무엇에 쓰는지, 왜 넣었는지, 아이폰에서 확인했는지."
        )

    extra = sorted(name for name in recorded if name not in declared)
    if extra:
        fail(
            "대장에는 있는데 app/pubspec.yaml 에서 사라진 부품: "
            + ", ".join(extra)
            + "\n뺐으면 대장에서도 지울 것."
        )

    kinds = [classify(n, versions.get(n, "")) for n in declared]
    native = kinds.count("네이티브")
    unknown = kinds.count("확인불가")
    summary = f"부품 {len(declared)}개 전부 대장에 있다 (네이티브 {native}개"
    if unknown:
        summary += f", 판정불가 {unknown}개 — pub cache 없음"
    print(f"✓ {summary})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
