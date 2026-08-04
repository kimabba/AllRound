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

한계:
    대장에 이름만 적으면 통과한다. "왜 넣었나"가 성의 없이 적히는 것까지는 막지
    못한다. 이 검사의 몫은 **부품이 조용히 늘어나는 것**을 막는 데까지다.
"""

from __future__ import annotations

import os
import re
import sys

try:
    import yaml
except ImportError:  # pragma: no cover
    print("❌ PyYAML 이 필요하다: pip install pyyaml")
    raise SystemExit(1)

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PUBSPEC = os.path.join(ROOT, "app", "pubspec.yaml")
LEDGER = os.path.join(ROOT, "docs", "team", "dependencies.md")
CACHE = os.path.expanduser("~/.pub-cache/hosted/pub.dev")

# Flutter SDK 가 넣어주는 것들 — 대장에 적을 대상이 아니다.
SDK_PACKAGES = {"flutter", "flutter_localizations", "flutter_test", "flutter_lints"}


def fail(message: str) -> None:
    print(f"❌ {message}")
    raise SystemExit(1)


def declared_dependencies() -> list[str]:
    spec = yaml.safe_load(open(PUBSPEC, encoding="utf-8")) or {}
    deps = spec.get("dependencies") or {}
    return sorted(name for name in deps if name not in SDK_PACKAGES)


def ledger_entries() -> set[str]:
    """대장 표의 첫 칸(`백틱으로 감싼 부품명`)만 읽는다."""
    text = open(LEDGER, encoding="utf-8").read()
    return set(re.findall(r"^\|\s*`([a-z0-9_]+)`\s*\|", text, flags=re.MULTILINE))


def classify(name: str, version: str) -> str:
    """설치된 패키지를 보고 네이티브인지 판정한다.

    pub cache 가 없으면(clean CI 등) 판정을 건너뛴다 — 이 검사의 본래 목적은
    '대장에 적혔는가'이고, 네이티브 판정은 사람을 돕는 부가 정보다.
    """
    directory = os.path.join(CACHE, f"{name}-{version}")
    manifest = os.path.join(directory, "pubspec.yaml")
    if not os.path.isfile(manifest):
        return "확인불가"
    meta = yaml.safe_load(open(manifest, encoding="utf-8")) or {}
    if (meta.get("flutter") or {}).get("plugin"):
        return "네이티브"
    if os.path.isfile(os.path.join(directory, "ffigen.yaml")) or os.path.isdir(
        os.path.join(directory, "hook")
    ):
        return "네이티브"
    return "순수 Dart"


def locked_versions() -> dict[str, str]:
    lock_path = os.path.join(ROOT, "app", "pubspec.lock")
    if not os.path.isfile(lock_path):
        return {}
    lock = yaml.safe_load(open(lock_path, encoding="utf-8")) or {}
    return {
        name: (info or {}).get("version", "")
        for name, info in (lock.get("packages") or {}).items()
    }


def main() -> int:
    declared = declared_dependencies()
    recorded = ledger_entries()

    missing = [name for name in declared if name not in recorded]
    extra = sorted(name for name in recorded if name not in declared)

    if missing:
        versions = locked_versions()
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

    if extra:
        fail(
            "대장에는 있는데 app/pubspec.yaml 에서 사라진 부품: "
            + ", ".join(extra)
            + "\n뺐으면 대장에서도 지울 것."
        )

    versions = locked_versions()
    native = [n for n in declared if classify(n, versions.get(n, "")) == "네이티브"]
    unknown = [n for n in declared if classify(n, versions.get(n, "")) == "확인불가"]
    summary = f"부품 {len(declared)}개 전부 대장에 있다 (네이티브 {len(native)}개"
    if unknown:
        summary += f", 판정불가 {len(unknown)}개 — pub cache 없음"
    print(f"✓ {summary})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
