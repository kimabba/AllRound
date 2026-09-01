#!/usr/bin/env bash
# 워크트리 정리 도우미 — 안전한 것만 골라 보여주고, 명시할 때만 지운다.
#
# 왜 필요한가:
#   워크트리는 소스만 나누고 빌드 산출물(app/build, .dart_tool)은 각자 새로 만든다.
#   Flutter 빌드 한 번에 GB 단위라 워크트리를 안 치우면 저장소가 수십 GB 로 붇는다.
#   (2026-08-19 실측: ar 폴더 12GB 중 11.4GB 가 워크트리 3곳의 빌드 산출물)
#
#   그런데 Claude Code 의 자동 정리는 **대화형 세션을 정상 종료할 때만** 걸린다.
#   `-p` 실행이나 창을 강제로 닫으면 안 돌고, 주기적 sweep 는 `--worktree` 로 만든
#   워크트리를 아예 건드리지 않는다. `git worktree add` 로 손수 만든 것도 마찬가지다.
#   그래서 나중에 아무 때나 돌릴 수 있는 이 스크립트가 필요하다.
#   근거: https://code.claude.com/docs/en/worktrees ("Clean up worktrees")
#
# `/clean_gone` 과 무엇이 다른가:
#   그쪽은 원격이 지워진 브랜치([gone])면 워크트리째 삭제한다. 그 판정만으로는
#   위험하다 — 2026-08-19 에 [gone] 인 워크트리에서 **머지되지 않은 커밋**을 찾았다.
#   같은 브랜치의 다른 커밋만 PR 로 나가고 하나가 남아 있었다. 그대로 지웠으면
#   사라졌을 작업이다. 이 스크립트는 커밋 단위로 main 반영 여부를 확인한다.
#
# squash 머지 판정의 한계 — 반드시 읽을 것:
#   PR 을 squash 로 머지하면 원본 커밋 해시가 main 에 남지 않으므로
#   `git log origin/main..HEAD` 는 이미 머지된 작업도 "미머지"로 보여준다.
#   그래서 커밋 제목으로 main 을 되짚는데, 이건 해시 대조가 아니라 **정황 증거**다.
#   같은 제목의 다른 커밋이 main 에 있으면 미머지를 머지됨으로 잘못 볼 수 있다
#   (2026-08-19 리뷰에서 실제로 재현됐다). 그래서 셋으로 좁혔다.
#     · 검색 범위를 분기점(merge-base) 이후로 제한한다. squash 커밋은 반드시
#       분기 이후에 들어오므로 정당하고, 대조 모수가 크게 준다.
#     · 제목이 비었으면 판정하지 않고 미머지로 둔다(--grep="" 는 전부 매치한다).
#     · 제목으로 추정한 건수를 SAFE 사유에 적어, --force 전에 사람이 본다.
#   `--grep` 은 제목이 아니라 메시지 전체에서 부분 문자열을 찾는다는 점도 유의.
#   확신이 필요하면 KEEP 으로 두고 직접 확인할 것. 이 도구는 후보를 좁힐 뿐이다.
#
# 사용:
#   bash scripts/qa/worktree_gc.sh            # 목록과 판정만 (아무것도 지우지 않음)
#   bash scripts/qa/worktree_gc.sh --force    # SAFE 로 판정된 것만 실제 삭제
set -euo pipefail

# cd 하기 전에 **호출자가 서 있는 곳**을 잡는다. cd 뒤에 잡으면 스크립트 파일이
# 든 체크아웃을 보호하게 되어, 다른 워크트리에서 메인의 사본을 실행할 때 자기가
# 선 폴더가 삭제 대상이 된다.
CALLER_PWD="$(pwd -P)"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

# 활성 세션 판정 창. 이보다 최근에 손댄 워크트리는 살아 있다고 보고 건드리지 않는다.
ACTIVE_WINDOW="${WORKTREE_GC_ACTIVE_WINDOW:-12 hours ago}"

# 날짜 문자열이 find 에 안 먹히면 recency 게이트가 조용히 꺼져 KEEP 이어야 할
# 워크트리가 SAFE 로 내려간다. 종료코드로는 못 잡는다 — macOS find 는 못 읽는
# 날짜를 에러 없이 통과시킨다(실측: exit 0). 그래서 **방금 만든 파일은 어떤
# 과거 기준으로도 반드시 매치된다**는 성질로 확인한다.
_probe="$(mktemp)"
if ! command find "$_probe" -newermt "$ACTIVE_WINDOW" -print -quit 2>/dev/null | grep -q .; then
  rm -f "$_probe"
  echo "❌ 활성 판정 창이 동작하지 않는다: '$ACTIVE_WINDOW'" >&2
  echo "   날짜를 못 읽었거나 창이 미래다. '12 hours ago' 같은 형식을 준다." >&2
  echo "   그대로 두면 '최근 수정' 검사가 꺼진 채 돌아 작업 중인 워크트리를 SAFE 로 본다." >&2
  exit 1
fi
rm -f "$_probe"
# 읽을 수 없는 날짜의 결말은 구현마다 다르고, 둘 다 안전한 쪽으로 끝난다:
#   · macOS(BSD): 조용히 "전부 매치" → 모든 워크트리가 KEEP → 아무것도 안 지운다
#   · GNU: 에러 → 위 검사가 걸려 멈춘다

GIT_COMMON="$(git rev-parse --git-common-dir)"
case "$GIT_COMMON" in /*) ;; *) GIT_COMMON="$ROOT/$GIT_COMMON" ;; esac

# 워크트리 경로는 공백을 담을 수 있다. awk $2 로 자르면 경로가 깨져 엉뚱한 곳을
# 보게 되므로 항상 접두사 길이로 잘라낸다("worktree " = 9자).
list_worktrees() {
  git worktree list --porcelain | awk '/^worktree /{ print substr($0, 10) }'
}

MAIN_WT="$(list_worktrees | head -1)"

# origin/main 을 최신으로. 낡은 기준이면 이미 머지된 것을 미머지로 보게 되는데
# 그건 KEEP 쪽(안전한 방향)이라 실패해도 계속 진행한다.
git fetch -q -p origin 2>/dev/null || echo "⚠️  fetch 실패 — 낡은 origin/main 기준으로 판정한다" >&2

BASE="origin/main"
git rev-parse --verify -q "$BASE" >/dev/null || BASE="$(git symbolic-ref -q --short refs/remotes/origin/HEAD || echo main)"

# 워크트리별 잠금 이유를 "경로<TAB>이유" 줄로 모은다.
# 연관배열(declare -A)은 bash 4+ 전용이라 쓰지 않는다 — macOS 기본 bash 는 3.2 다.
LOCKS="$(
  git worktree list --porcelain | awk '
    /^worktree /{ wt = substr($0, 10) }
    /^locked/   { reason = (length($0) > 7) ? substr($0, 8) : "(이유 없음)"
                  printf "%s\t%s\n", wt, reason }
  '
)"

row() { printf '%-28s %7s %-8s %s\n' "$1" "$2" "$3" "$4"; }

row "WORKTREE" "SIZE" "VERDICT" "REASON"
printf '%s\n' "--------------------------------------------------------------------------------"

SAFE_LIST=""

while IFS= read -r wt; do
  [ -z "$wt" ] && continue
  name="$(basename "$wt")"
  # du 는 권한 오류에도 합계를 찍고 nonzero 로 끝나므로 첫 줄만 취한다.
  size="$(du -sh "$wt" 2>/dev/null | head -1 | cut -f1 || true)"
  [ -z "$size" ] && size="?"

  if [ "$wt" = "$MAIN_WT" ]; then
    row "$name" "$size" "SKIP" "메인 체크아웃"; continue
  fi
  # 하위 폴더(app/ 등)에 서서 실행해도 보호해야 한다 — 완전 일치만 보면 샌다.
  case "$CALLER_PWD" in
    "$wt"|"$wt"/*)
      row "$name" "$size" "SKIP" "지금 이 세션이 쓰는 중"; continue ;;
  esac

  lock_reason="$(printf '%s\n' "$LOCKS" | awk -F'\t' -v w="$wt" '$1 == w { print $2; exit }')"
  if [ -n "$lock_reason" ]; then
    row "$name" "$size" "KEEP" "잠김: $lock_reason"; continue
  fi

  # 워크트리가 성한지 먼저 본다. 오래 방치된 것일수록 .git 이 깨져 있을 확률이
  # 높은데, 가드가 없으면 git -C 실패가 set -e 로 스크립트 전체를 죽인다.
  if ! git -C "$wt" rev-parse --git-dir >/dev/null 2>&1; then
    row "$name" "$size" "KEEP" "git 상태를 읽을 수 없다 — 손으로 확인할 것"; continue
  fi

  # 최근에 손댔으면 살아 있는 세션일 수 있다. 빌드 산출물은 빼고 소스 쪽만 훑는다.
  # -print -quit 로 첫 결과에서 멈춘다 — 파이프+head 는 SIGPIPE 로 판정을 뒤집는다.
  # `command find`: 셸에 find 를 감싼 함수/별칭이 있으면 -newermt 자연어를 못 받는
  # 구현(bfs 등)으로 새어 판정이 조용히 무너진다.
  # depth 4 까지: app/lib/screens/foo.dart 같은 제자리 편집을 잡으려면 얕으면 안 된다.
  recent="$(command find "$wt" -maxdepth 4 -newermt "$ACTIVE_WINDOW" \
              -not -path "*/build/*" -not -path "*/.dart_tool/*" -print -quit 2>/dev/null || true)"
  # 워크트리 파일이 조용해도 체크아웃·커밋이 있었으면 reflog 에 줄이 붙는다.
  # `logs/HEAD` 를 본다 — 커밋·체크아웃 양쪽에 append 되고 `git status` 는 건드리지
  # 않는다(실측). `HEAD` 파일은 안 된다: **브랜치 워크트리에서는 커밋해도 HEAD 의
  # mtime 이 그대로**고(HEAD 는 ref 이름만 담는다) detached 일 때만 바뀐다.
  # 디렉터리 자체나 index 도 안 된다 — git 이 조회만 해도 갱신돼(이 스크립트의
  # status 호출 포함) 전부 KEEP 이 되어 도구가 무력해진다.
  wt_admin="$(git -C "$wt" rev-parse --git-dir 2>/dev/null || true)"
  if [ -z "$recent" ] && [ -n "$wt_admin" ] && [ -f "$wt_admin/logs/HEAD" ]; then
    recent="$(command find "$wt_admin/logs/HEAD" -newermt "$ACTIVE_WINDOW" -print -quit 2>/dev/null || true)"
  fi
  if [ -n "$recent" ]; then
    row "$name" "$size" "KEEP" "최근 ${ACTIVE_WINDOW} 안에 손댐 — 작업 중일 수 있다"; continue
  fi

  dirty="$(git -C "$wt" status --porcelain 2>/dev/null | wc -l | tr -d ' ' || true)"
  if [ "${dirty:-0}" != "0" ]; then
    row "$name" "$size" "KEEP" "미커밋·untracked ${dirty}건"; continue
  fi

  # squash 대조 범위: 이 워크트리가 갈라져 나온 지점 이후의 main 만 본다.
  wt_head="$(git -C "$wt" rev-parse HEAD 2>/dev/null || true)"
  fork=""
  [ -n "$wt_head" ] && fork="$(git merge-base "$BASE" "$wt_head" 2>/dev/null || true)"
  scope="$BASE"
  [ -n "$fork" ] && scope="$fork..$BASE"

  unmerged=0
  guessed=0
  first_missing=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    subject="${line#* }"
    hit=""
    # 제목이 비면 --grep="" 가 모든 커밋에 매치된다. 판정하지 않고 미머지로 둔다.
    if [ -n "$subject" ]; then
      # 파이프를 쓰지 않는다 — head 로 끊으면 git 이 SIGPIPE 로 죽고 pipefail 이
      # 판정을 "미머지"로 뒤집는다(흔한 제목일수록 잘 터진다).
      hit="$(git log "$scope" -1 --format=%h --fixed-strings --grep="$subject" 2>/dev/null || true)"
    fi
    if [ -n "$hit" ]; then
      guessed=$((guessed + 1))
    else
      unmerged=$((unmerged + 1))
      [ -z "$first_missing" ] && first_missing="$line"
    fi
  done < <(git -C "$wt" log "$BASE"..HEAD --format="%h %s" 2>/dev/null || true)

  if [ "$unmerged" != "0" ]; then
    row "$name" "$size" "KEEP" "미머지 커밋 ${unmerged}건: ${first_missing}"; continue
  fi

  # detached HEAD 는 워크트리 admin 디렉터리가 커밋의 유일한 참조다. 브랜치가
  # 있으면 워크트리를 지워도 브랜치가 커밋을 붙잡지만, detached 는 그 안전망이
  # 없어 삭제 즉시 unreachable 이 된다. 제목 추정(해시 대조 아님)까지 겹치면
  # 오판이 곧 커밋 소실이므로, 그 조합만은 사람이 보게 KEEP 으로 둔다.
  if [ "$guessed" != "0" ] && ! git -C "$wt" symbolic-ref -q HEAD >/dev/null 2>&1; then
    row "$name" "$size" "KEEP" "detached + 제목 추정 ${guessed}건 — 브랜치가 없어 지우면 커밋을 잃는다"
    continue
  fi

  if [ "$guessed" != "0" ]; then
    row "$name" "$size" "SAFE" "미커밋 없음 · ${guessed}건은 제목 일치로 머지 추정(해시 대조 아님)"
  else
    row "$name" "$size" "SAFE" "미커밋 없음 · main 에 없는 커밋 없음"
  fi
  SAFE_LIST="${SAFE_LIST}${wt}
"
done < <(list_worktrees)

echo
SAFE_COUNT="$(printf '%s' "$SAFE_LIST" | grep -c . || true)"
if [ "${SAFE_COUNT:-0}" = "0" ]; then
  echo "지울 수 있는 워크트리가 없다."
  exit 0
fi

if [ "$FORCE" -eq 0 ]; then
  echo "SAFE ${SAFE_COUNT}개. 실제로 지우려면 --force 를 붙인다:"
  echo "  bash scripts/qa/worktree_gc.sh --force"
  echo
  echo "'제목 일치로 머지 추정'이 붙은 항목은 해시로 확인한 게 아니다 — 지우기 전에 눈으로 볼 것."
  echo "KEEP 은 손대지 않는다. 미머지 커밋이 있으면 PR 로 살린 뒤 다시 돌린다."
  exit 0
fi

printf '%s\n' "$SAFE_LIST" | while IFS= read -r wt; do
  [ -z "$wt" ] && continue
  echo "제거: $wt"
  # --force 를 쓰지 않는다. 판정 이후 누가 손댔으면 git 이 거부하게 두는 편이
  # 공짜 이중 안전장치다(SAFE 판정 시점에 이미 clean 을 확인했다).
  # gitignore 된 파일(.env, 로컬 supabase 상태)은 dirty 에 안 잡혀 함께 사라진다.
  git worktree remove "$wt" || echo "  → 건너뜀: git 이 거부했다(그 사이 변경됐을 수 있다)"
done
git worktree prune
echo "✅ 정리 완료. 브랜치는 남긴다 — 커밋 도달 가능성을 지키는 마지막 안전망이라"
echo "   브랜치 정리는 /clean_gone 에 맡긴다."
