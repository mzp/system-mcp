---
name: skill-eval
description: Run the end-to-end eval harness for the apple-reminder / apple-calendar hermes skills (skills/eval/run.sh). Use when asked to test, eval, verify, or regression-check the skills — e.g. "test the skills", "スキルのテストして", "minimaxで通るか確認して", or after editing a skills/*/SKILL.md. Drives real Japanese prompts through hermes under a chosen model and checks the systemmcp command the agent emitted plus the real (self-cleaning) effect on Reminders.
---

# skill-eval

Repeatable end-to-end check that the `skills/apple-reminder` and `skills/apple-calendar`
hermes skills still work — including with a weak model (the harness defaults to
`minimax/minimax-m3`, the floor we want them to pass). Use it after editing any
`skills/*/SKILL.md`, or whenever asked to test/verify the skills.

## How to run

From the repo root:

```sh
skills/eval/run.sh             # all cases
skills/eval/run.sh kitchen     # one case: today | shop_list | cal_tomorrow | kitchen | tz_floating
MODEL=qwen/qwen3.7-plus skills/eval/run.sh    # test a different model (e.g. the live default)
```

Each case prints `PASS`/`FAIL`; the script exits non-zero if any case fails. Report the
summary line and any FAILs to the user; on failure, show the case and what was expected.

## What it does (and why it's safe to re-run)

- Drives prompts through `hermes chat -m <model> -q "…"`, **wrapped in Claude.app's
  `disclaimer`** so hermes gets the same TCC `fullAccess` as the gateway (a bare
  `hermes chat` from here is a different TCC responsible process → `notDetermined`;
  see hermes-setup CLAUDE.md gotcha #9). Without that wrapper the cases mis-fail.
- Checks the actual `~/.local/bin/systemmcp …` command the agent emitted (hermes prints
  it in the transcript), and for the write case the real net effect on Reminders.
- **Self-cleaning:** the `kitchen` case ("キッチンペーパーを買い物リストに追加して")
  snapshots the 買い物 list ids, runs the prompt, diffs to find exactly what was added,
  verifies it, then deletes only those — so the user's data is left unchanged. Read/list
  and calendar cases don't mutate anything.

## Cases

| id | prompt (JP) | passes when |
|---|---|---|
| `today` | 今日のリマインダー見せて | emits `reminders list --filter today` |
| `shop_list` | 買い物リストに何が入ってる？ | emits a `reminders list` scoped to 買い物 |
| `cal_tomorrow` | 明日の予定を教えて | emits `events list` over a `T00:00:00`→`T00:00:00` day range |
| `kitchen` | [テスト用]キッチンペーパーを買い物リストに追加して | emits a correct `reminders add … --list 買い物` and a [テスト用]キッチンペーパー reminder really appears (then is cleaned up) |
| `tz_floating` | どこにいても現地時間の朝9時に鳴るようリマインド | emits `reminders add … --timezone floating` and the created reminder really has `floating: true` (then is cleaned up) |

## Requirements / gotchas

- Runs only on this Mac: needs hermes installed (`~/hermes-setup`), the signed
  `~/.local/bin/systemmcp` (`make install`), the granted TCC permission, and
  `/Applications/Claude.app/Contents/Helpers/disclaimer`. Not a CI test.
- Overridable via env: `MODEL`, `BIN`, `DISCLAIMER`, `HERMES_DIR` (see the script header).
- A weak model sometimes fires `add` twice; the `kitchen` case tolerates that (it still
  cleans up all added items) — it asserts "can add", not "added exactly once".
- To add a case: add a `case_<id>()` function and list its id in the dispatch loop at the
  bottom of `skills/eval/run.sh`, then document it in the table above.
