#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

root = Path.cwd()
# Scan files Git would see: tracked files plus untracked files that are not ignored.
# Local ignored .env files may contain real secrets and should not make day-to-day harness runs fail.
result = subprocess.run(
    ['git', 'ls-files', '--cached', '--others', '--exclude-standard'],
    cwd=root,
    text=True,
    capture_output=True,
    check=True,
)
paths = [Path(line) for line in result.stdout.splitlines() if line.strip()]
exclude_files = {'pubspec.lock'}
exclude_paths = {
    # Firebase client config keys identify an app and are intentionally shipped
    # in mobile binaries; server/service-account credentials remain scanned.
    'app/android/app/google-services.json',
    'app/ios/Runner/GoogleService-Info.plist',
}
# Keep this list intentionally conservative to avoid noisy placeholder matches.
patterns = {
    'GitHub token': re.compile(r'gh[pousr]_[A-Za-z0-9_]{30,}'),
    'OpenAI-style key': re.compile(r'sk-[A-Za-z0-9]{32,}'),
    'Google API key': re.compile(r'AIza[0-9A-Za-z_-]{30,}'),
    'Supabase JWT': re.compile(r'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}'),
    'Supabase secret key': re.compile(r'sb_secret_[A-Za-z0-9_-]{16,}'),
    'PEM private key': re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
    'Service account JSON': re.compile(r'"type"\s*:\s*"service_account"'),
}
allow_placeholder_words = ('example', 'placeholder', '<', '...', 'YOUR_', 'REPLACE_ME')
findings: list[str] = []

for rel in paths:
    path = root / rel
    if not path.is_file() or path.name in exclude_files or rel.as_posix() in exclude_paths:
        continue
    try:
        text = path.read_text(encoding='utf-8')
    except UnicodeDecodeError:
        continue
    for line_no, line in enumerate(text.splitlines(), start=1):
        if any(word in line for word in allow_placeholder_words):
            continue
        for name, pattern in patterns.items():
            if pattern.search(line):
                findings.append(f'{rel}:{line_no}: possible {name}')

if findings:
    print('❌ possible secrets found in git-visible files:', file=sys.stderr)
    for finding in findings[:50]:
        print(f'  {finding}', file=sys.stderr)
    if len(findings) > 50:
        print(f'  ... and {len(findings) - 50} more', file=sys.stderr)
    raise SystemExit(1)

print('✓ no obvious secrets found in git-visible files')
PY
