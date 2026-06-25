#!/usr/bin/env bash
#
# E2E test harness for the apple-reminder / apple-calendar hermes skills.
#
# Drives real Japanese prompts through hermes with a chosen model, then checks the
# `systemmcp` command the agent actually emitted (hermes prints it in the transcript)
# and, for write cases, the real net effect on Reminders — cleaning up after itself.
#
# Requires this Mac's TCC grant for Reminders/Calendar. hermes via the host terminal
# is NOT the gateway's TCC responsible process, so we wrap every call in Claude.app's
# `disclaimer` to reproduce the gateway's fullAccess (see hermes-setup CLAUDE.md gotcha #9).
#
# Usage:
#   skills/eval/run.sh            # run all cases
#   skills/eval/run.sh kitchen    # run one case by id
#   MODEL=qwen/qwen3.7-plus skills/eval/run.sh   # override the model under test
#
set -uo pipefail

MODEL="${MODEL:-minimax/minimax-m3}"
BIN="${BIN:-$HOME/.local/bin/systemmcp}"
DISCLAIMER="${DISCLAIMER:-/Applications/Claude.app/Contents/Helpers/disclaimer}"
HERMES_DIR="${HERMES_DIR:-$HOME/hermes-setup}"
SHOP="買い物"

PASS=0
FAIL=0

# Run a prompt through hermes under the model being tested; emit the full transcript.
ask() { ( cd "$HERMES_DIR" && "$DISCLAIMER" hermes chat -m "$MODEL" -q "$1" 2>&1 ); }

# Call the systemmcp binary directly (for snapshots / cleanup), disclaimed for fullAccess.
sysmcp() { "$DISCLAIMER" "$BIN" "$@" 2>/dev/null; }

# UUID reminder ids currently in the shopping list (one per line).
shop_ids() { sysmcp reminder reminders list --filter all --list "$SHOP" | grep -oiE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'; }

ok()   { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; }
have() { grep -qiF -- "$2" <<<"$1"; }   # have "$transcript" "needle"

# ── Read case: today's reminders → expects `reminders list --filter today` ──────────
case_today() {
  echo "[today] 今日のリマインダー見せて"
  local t; t="$(ask 'apple-reminderスキルで今日のリマインダーを見せて')"
  if have "$t" "reminders list" && have "$t" "--filter today"; then
    ok "emitted: reminders list --filter today"
  else
    bad "did not emit 'reminders list --filter today'"
  fi
}

# ── Read case: shopping list contents → expects `--list 買い物` ──────────────────────
case_shop_list() {
  echo "[shop_list] 買い物リストに何が入ってる？"
  local t; t="$(ask 'apple-reminderスキルで買い物リストに何が入ってるか教えて')"
  if have "$t" "reminders list" && have "$t" "$SHOP"; then
    ok "emitted: reminders list scoped to 買い物"
  else
    bad "did not scope the list to 買い物"
  fi
}

# ── Calendar case: tomorrow → expects a single-day ISO range ────────────────────────
case_cal_tomorrow() {
  echo "[cal_tomorrow] 明日の予定を教えて"
  local t; t="$(ask 'apple-calendarスキルで明日の予定を教えて')"
  if have "$t" "events list" && grep -qE 'T00:00:00' <<<"$t"; then
    ok "emitted: events list over a 00:00→00:00 day range"
  else
    bad "did not build a T00:00:00 single-day range"
  fi
}

# ── Write case (self-cleaning): add キッチンペーパー to the shopping list ────────────
# A duplicate-titled item already exists in 買い物, so we diff ids before/after to find
# exactly what the agent added, verify it, and delete only that.
case_kitchen() {
  echo "[kitchen] キッチンペーパーを買い物リストに追加して"
  local before after added t
  before="$(shop_ids | sort)"
  t="$(ask 'apple-reminderスキルで、キッチンペーパーを買い物リストに追加して')"
  after="$(shop_ids | sort)"
  added="$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after"))"

  # 1. emitted the right command
  if have "$t" "reminders add" && have "$t" "キッチンペーパー" && have "$t" "$SHOP"; then
    ok "emitted: reminders add --title キッチンペーパー --list 買い物"
  else
    bad "did not emit a correct 'reminders add' for 買い物"
  fi

  # 2. real effect: a new キッチンペーパー reminder appeared in 買い物.
  # (A duplicate of the same title may already exist; we only judge what was added.
  # A weak model occasionally fires `add` twice — that still counts as "can add".)
  local n match title; n="$(printf '%s' "$added" | grep -c .)"; match=0
  while read -r id; do
    [ -z "$id" ] && continue
    title="$(sysmcp reminder reminders list --filter all --list "$SHOP" \
      | python3 -c 'import sys,json;d=json.load(sys.stdin);i=sys.argv[1];print(next((r["title"] for r in d if r["id"]==i),""))' "$id" 2>/dev/null)"
    [ "$title" = "キッチンペーパー" ] && match=$((match+1))
  done <<<"$added"
  if [ "$match" -ge 1 ]; then
    ok "added $match キッチンペーパー reminder(s) to 買い物 (of $n new)"
  else
    bad "no new キッチンペーパー reminder appeared (n=$n)"
  fi

  # 3. cleanup: delete only what we added
  if [ -n "$added" ]; then
    while read -r id; do [ -n "$id" ] && sysmcp reminder reminders delete "$id" >/dev/null; done <<<"$added"
    echo "  cleanup: deleted $n added reminder(s)"
  fi
}

run() {
  case "$1" in
    today)        case_today ;;
    shop_list)    case_shop_list ;;
    cal_tomorrow) case_cal_tomorrow ;;
    kitchen)      case_kitchen ;;
    *) echo "unknown case: $1" >&2; exit 2 ;;
  esac
}

echo "model under test: $MODEL"
echo
if [ $# -ge 1 ]; then
  run "$1"
else
  for c in today shop_list cal_tomorrow kitchen; do run "$c"; echo; done
fi
echo
echo "── result: $PASS passed, $FAIL failed ──"
[ "$FAIL" -eq 0 ]
