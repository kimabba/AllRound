#!/usr/bin/env bash
# 프로덕션의 **공개 데이터만** 로컬 Supabase 로 내려받는다.
#
# 왜 필요한가:
#   개발은 로컬 DB 를 보게 갈랐는데(app/.env.local), 로컬 시드에는 크롤러가 모은
#   대회·구장·협회랭킹이 거의 없다. 그러면 구장 검색·협회 랭킹 화면이 빈 채로
#   보이고, 결국 "개발할 때만 잠깐" 프로덕션에 다시 붙게 된다. 그 유혹을 없애려면
#   로컬에도 같은 데이터가 있어야 한다.
#
# 무엇을 가져오고 무엇을 안 가져오나:
#   가져오는 것은 **크롤러가 공개 웹에서 모은 자료와 참조표**뿐이다. 사람이 만든
#   것(계정·클럽·채팅·신고·기록)과 로그는 가져오지 않는다. 크기가 아니라 성격의
#   문제다 — 실사용자의 이름·이메일·대화를 개발용 노트북에 복사하는 순간 그건
#   처리방침에 없는 취급이 되고, 노트북 분실이 곧 유출이 된다.
#
#   그래서 **화이트리스트**로 간다. 목록에 적힌 것만 가져온다. 블랙리스트(제외 목록)
#   방식이면 새 테이블이 생겼을 때 조용히 딸려오는데, 화이트리스트는 새 테이블이
#   기본 제외다. 아래 INCLUDE·EXCLUDE 어디에도 없는 테이블이 발견되면 **멈춘다** —
#   사람이 분류할 때까지 진행하지 않는다.
#
# 사용:
#   bash scripts/qa/sync_local_public_data.sh            # 무엇을 할지만 보여준다
#   bash scripts/qa/sync_local_public_data.sh --apply    # 실제로 내려받아 적재
#
# 전제: supabase link 가 되어 있고 로컬 스택이 떠 있어야 한다(supabase start).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

LOCAL_DB="${LOCAL_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"

# ── 분류표 ────────────────────────────────────────────────────────────
# 크롤러가 공개 웹에서 모은 자료 + 코드가 참조하는 표. 사람이 만든 것은 없다.
INCLUDE="
app_release_gate
crawl_sources
futsal_tournament_details
grades
intent_examples
org_player_results
org_ranking_snapshots
org_rankings
regions
rule_articles
tennis_divisions
tennis_orgs
tennis_tournament_details
tournaments
ugc_moderation_terms
venues
"

# 가져오지 않는 것. 여기 적는 이유는 "새 테이블 감지" 때문이다 — 목록에 없는
# 테이블이 나타나면 분류를 강제하려면 제외 대상도 명시돼 있어야 한다.
#
# 개인정보·사용자 생성물 외에 **캐시·조회 기록**도 뺀다. 예를 들어
# org_player_history_fetches 는 "언제 가져왔는지"를 담는데, 프로덕션 값을 넣으면
# 로컬이 이미 조회했다고 오판해 다시 안 가져온다.
EXCLUDE="
chat_messages
chat_rate_limit
club_bans
club_chat_messages
club_chat_participants
club_chat_threads
club_dues_audit
club_dues_payments
club_dues_periods
club_event_attendees
club_events
club_favorites
club_inquiry_messages
club_inquiry_threads
club_join_requests
club_members
club_post_comments
club_post_mentions
club_posts
club_recruiting_posts
clubs
crawl_audit
crawl_documents
device_tokens
edge_invocations
gemini_usage
match_entries
match_rounds
notifications
org_player_links
org_player_history_fetches
org_ranking_suppressions
qa_cache
rate_limits
schedule_shares
tournament_favorites
ugc_reports
user_blocks
user_penalties
user_sports
user_tennis_orgs
users
"

norm() { printf '%s\n' "$1" | tr -s '[:space:]' '\n' | grep -v '^$' | sort; }

INCLUDE_SORTED="$(norm "$INCLUDE")"
EXCLUDE_SORTED="$(norm "$EXCLUDE")"

# 스키마는 로컬에서 읽는다. 마이그레이션이 같으니 프로덕션과 같은 목록이고,
# 프로덕션에 접속하지 않고도 분류 검사를 할 수 있다.
if ! ALL="$(psql "$LOCAL_DB" -tAc "select tablename from pg_tables where schemaname='public' order by 1" 2>/dev/null)"; then
  echo "❌ 로컬 Supabase 에 접속할 수 없다: $LOCAL_DB" >&2
  echo "   먼저 'supabase start' 로 스택을 올린다." >&2
  exit 1
fi
ALL_SORTED="$(norm "$ALL")"

# ── 새 테이블 감지 — 분류 안 된 게 있으면 멈춘다 ──────────────────────
KNOWN_SORTED="$(printf '%s\n%s\n' "$INCLUDE_SORTED" "$EXCLUDE_SORTED" | grep -v '^$' | sort)"
UNCLASSIFIED="$(comm -23 <(printf '%s\n' "$ALL_SORTED") <(printf '%s\n' "$KNOWN_SORTED"))"
if [ -n "$UNCLASSIFIED" ]; then
  echo "❌ 분류되지 않은 테이블이 있다. 가져올지 말지 정하기 전에는 진행하지 않는다:" >&2
  printf '   - %s\n' $UNCLASSIFIED >&2
  echo "" >&2
  echo "   이 스크립트의 INCLUDE(가져옴) 또는 EXCLUDE(안 가져옴) 에 추가할 것." >&2
  echo "   사람이 만든 것·개인정보·로그면 EXCLUDE 다. 헷갈리면 EXCLUDE 가 안전하다." >&2
  exit 1
fi

# 목록에는 있는데 DB 에 없는 것(테이블 삭제 후 목록 정리 누락) 도 알려준다.
STALE="$(comm -13 <(printf '%s\n' "$ALL_SORTED") <(printf '%s\n' "$KNOWN_SORTED"))"
[ -n "$STALE" ] && { echo "⚠️  DB 에 없는데 목록에 남은 테이블(정리 필요):"; printf '   - %s\n' $STALE; echo ""; }

INCLUDE_COUNT="$(printf '%s\n' "$INCLUDE_SORTED" | grep -c . || true)"
EXCLUDE_COUNT="$(printf '%s\n' "$EXCLUDE_SORTED" | grep -c . || true)"
echo "가져올 테이블 ${INCLUDE_COUNT}개 · 가져오지 않을 테이블 ${EXCLUDE_COUNT}개 (전체 $(printf '%s\n' "$ALL_SORTED" | grep -c .)개)"
echo ""
printf '%s\n' "$INCLUDE_SORTED" | sed 's/^/  + /'
echo ""

# TRUNCATE ... CASCADE 는 이 테이블들을 참조하는 다른 테이블도 함께 비운다.
# 무엇이 딸려 가는지는 실제로 해 봐야 안다 — 트랜잭션 안에서 돌리고 되돌린다.
CASCADE_HIT="$(
  printf 'BEGIN; TRUNCATE %s CASCADE; ROLLBACK;' \
    "$(printf '%s\n' "$INCLUDE_SORTED" | sed 's/^/public./' | paste -sd, -)" \
  | psql "$LOCAL_DB" -q 2>&1 | sed -n 's/^NOTICE:  truncate cascades to table "\(.*\)"$/\1/p' | sort -u
)"
if [ -n "$CASCADE_HIT" ]; then
  echo "⚠️  아래 테이블도 함께 비워진다 (위 테이블을 참조하고 있어서다):"
  printf '%s\n' "$CASCADE_HIT" | sed 's/^/  - /'
  echo "   로컬 시드·페르소나가 여기 들어 있으면 같이 사라진다."
  echo "   되돌리려면 'supabase db reset' 을 돌린 뒤 이 스크립트를 다시 실행한다."
  echo ""
fi

if [ "$APPLY" -eq 0 ]; then
  echo "실제로 내려받아 적재하려면 --apply 를 붙인다:"
  echo "  bash scripts/qa/sync_local_public_data.sh --apply"
  exit 0
fi

# ── 덤프 ──────────────────────────────────────────────────────────────
# supabase CLI 에 맡긴다. 원격이 PG17 이라 로컬 pg_dump(14) 로는 못 뜨고, CLI 가
# 도커로 맞는 버전을 쓰고 임시 로그인 롤도 알아서 만든다.
# 화이트리스트 옵션(--table)이 없어 "전체 - INCLUDE" 를 -x 로 넘긴다. 위의 분류
# 검사를 통과했으므로 이 목록은 전체를 덮는다.
DUMP="$(mktemp -t local_public_data)"
trap 'rm -f "$DUMP"' EXIT

XARGS=()
while IFS= read -r t; do
  [ -z "$t" ] && continue
  XARGS+=(-x "public.$t")
done < <(printf '%s\n' "$EXCLUDE_SORTED")

echo "프로덕션에서 공개 데이터를 내려받는다 (읽기만 한다)..."
supabase db dump --linked --data-only --schema public "${XARGS[@]}" -f "$DUMP"

# 받은 파일에 가져오지 말아야 할 테이블이 섞였는지 되본다 — 제외 인자가 먹지
# 않았거나 CLI 동작이 바뀌었을 때를 위한 최후 방어다.
LEAKED=""
while IFS= read -r t; do
  [ -z "$t" ] && continue
  if grep -qE "(COPY|INSERT INTO) \"?public\"?\.\"?${t}\"?[ (]" "$DUMP"; then
    LEAKED="${LEAKED}${t} "
  fi
done < <(printf '%s\n' "$EXCLUDE_SORTED")
if [ -n "$LEAKED" ]; then
  echo "❌ 가져오면 안 되는 테이블이 덤프에 들어 있다. 적재하지 않고 파일을 지운다:" >&2
  echo "   $LEAKED" >&2
  exit 1
fi

echo "받은 크기: $(du -h "$DUMP" | cut -f1)"

# ── 적재 ──────────────────────────────────────────────────────────────
# 로컬을 향하는지 다시 확인한다. 이 스크립트가 프로덕션에 쓰는 일은 없어야 한다.
case "$LOCAL_DB" in
  *127.0.0.1*|*localhost*) ;;
  *) echo "❌ 적재 대상이 로컬이 아니다: $LOCAL_DB" >&2; exit 1 ;;
esac

TRUNCATE_LIST="$(printf '%s\n' "$INCLUDE_SORTED" | sed 's/^/public./' | paste -sd, -)"
echo "로컬의 해당 테이블을 비우고 적재한다..."
# 비우기와 적재를 **한 트랜잭션**으로 묶는다. 따로 돌리면 적재가 중간에 실패했을 때
# 비우기만 남아 로컬 DB 가 통째로 빈 상태가 된다(실제로 겪었다).
{ echo "BEGIN;"; echo "TRUNCATE $TRUNCATE_LIST CASCADE;"; cat "$DUMP"; echo "COMMIT;"; } \
  | psql "$LOCAL_DB" -q -v ON_ERROR_STOP=1 --single-transaction

echo ""
echo "✅ 완료. 로컬 현황:"
psql "$LOCAL_DB" -tAc "
  select '  tournaments='||(select count(*) from tournaments)
      || ' venues='||(select count(*) from venues)
      || ' org_rankings='||(select count(*) from org_rankings)
      || ' rule_articles='||(select count(*) from rule_articles)"
echo ""
echo "TRUNCATE ... CASCADE 라 이 테이블들을 참조하던 로컬 데이터(즐겨찾기 등)도 함께"
echo "지워졌을 수 있다. 페르소나·시드를 되돌리려면 'supabase db reset' 후 다시 돌린다."
