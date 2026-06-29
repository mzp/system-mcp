---
name: apple-reminder
description: View, add, update, complete, and delete macOS Reminders, and manage reminder lists, via the systemmcp CLI. Always use this skill for anything about reminders, to-dos, shopping lists, or reminder lists — including Japanese requests like 「リマインダー追加して」「〇〇をリマインドして」「買い物リストに〇〇を追加して」「買い物リストに〇〇足して」「リストに〇〇を入れて」「今日のリマインダー見せて」「やることリスト確認」「リマインダー完了にして」「リマインダー消して」「リマインダーリスト作って」. Adding an item to a named list (買い物・やること etc.) — whether phrased 追加して／足して／入れて — always goes through this skill. Calendar events are handled by the separate apple-calendar skill.
---

# apple-reminder

Operate macOS Reminders by running the `systemmcp` CLI with the **terminal tool**. Run the host binary at the literal path below — do not invent any other path:

```
~/.local/bin/systemmcp reminder <subcommand> [options]
```

Follow the recipes below exactly. Use only the flags shown here; never invent flags, values, or subcommands.

## How to read a result

- **Success → JSON on stdout.** Shapes: `reminders list` and `complete` return a JSON **array**; `add` and `update` return one JSON **object**; `delete` returns `{"deleted":[...ids]}`; `lists list` returns an array.
- **Failure → a line starting with `Error:` on stderr, and stdout is empty.** Example: `Error: Invalid argument: unknown filter 'bogus'. ...`. When you see an `Error:` line (or stdout is not JSON), tell the user what failed and stop. Do not retry with guessed flags.
- The leading `... info systemmcp: ... authorization` log line on stderr is noise — ignore it.
- If `reminder status` is not `fullAccess`, say there is no access to Reminders and stop.

## Dates — read before passing any date

A date/time argument must be **exactly one of these forms**. Anything else is rejected with `Error: ... could not parse`:

- `today` or `tomorrow`
- a signed relative offset from now: `+1h`, `+30m`, `+1h30m`, `-2d`, `+3d` (the sign is required)
- a full ISO8601 datetime you build from the conversation's current date, e.g. `2026-06-25T09:00:00`

**Never pass words like `next week`, `来week`, `来週`, `morning`, `朝`, `週末`.** Convert first. For "tomorrow 9am", compute the ISO datetime from today's date in context. For listing, prefer the filter presets below so you don't have to compute dates at all.

## Time zone (`--timezone`, on add / update)

Controls how a due time is anchored. Three choices:

| `--timezone` value | Meaning | Use when |
|---|---|---|
| *(omitted — default)* | Anchored to the device's **local zone** — a concrete moment. | Normal case. Just leave it off. |
| `floating` (or `none`) | **No zone** — fires at that wall-clock time wherever the device is. | "9am, wherever I am" — daily/travel reminders that must not shift across time zones. |
| an IANA name / abbreviation, e.g. `America/New_York`, `EST`, `Asia/Tokyo` | **Fixed** to that zone's absolute moment; an offset-less `--due` is also read in that zone. | "10am New York time" — a time tied to a specific place. |

Only pass `--timezone floating` or a named zone when the user's intent clearly calls for it; otherwise omit it (local). In the result, `floating: true` and a `dueDate` without an offset means floating; `floating: false` with a `dueDate` offset (e.g. `2026-06-26T09:00:00-07:00`) and a `timeZone` field means anchored.

## Quoting

Always wrap titles, notes, and list names in double quotes — they usually contain spaces or Japanese: `--title "牛乳を買う"`, `--list "買い物"`.

## List reminders

```
~/.local/bin/systemmcp reminder reminders list [--filter <preset>] [--list "<name|id>"] [--start <date>] [--end <date>]
```

Pick the filter from this table; do not compute date ranges when a preset fits:

| User asks (examples) | Command |
|---|---|
| 今日の / today's | `reminder reminders list --filter today` |
| 明日の / tomorrow's | `reminder reminders list --filter tomorrow` |
| 今週の / this week | `reminder reminders list --filter week` |
| 期限切れ / overdue | `reminder reminders list --filter overdue` |
| これからの / upcoming | `reminder reminders list --filter upcoming` |
| 完了済み / completed | `reminder reminders list --filter completed` |
| 全部 / everything | `reminder reminders list --filter all` |
| 買い物リストの中身 | `reminder reminders list --filter all --list "買い物"` |

Each item looks like (trimmed):

```json
{ "id": "8B47BE84-8D09-463C-822E-28AE480EBAF7", "title": "キッチンペーパー",
  "list": "買い物", "completed": false, "priority": "none" }
```

The `id` is what every other operation needs.

## Add a reminder

```
~/.local/bin/systemmcp reminder reminders add --title "<title>" [--list "<name|id>"] [--due <date>] [--notes "<notes>"] [--priority <none|low|medium|high>]
```

Optional location trigger (only if the user asks for an arrive/leave reminder at a place):
`--location "<address or place>" [--proximity enter|leave] [--radius <meters>]` (default proximity `enter`; the place must geocode or it errors).
Optional `--timezone` controls the time anchor — see **Time zone** above (default = local; `floating` = travel-proof; a zone name = fixed to that place).

Example — "buy milk on the shopping list":
```
~/.local/bin/systemmcp reminder reminders add --title "牛乳を買う" --list "買い物"
```
Returns the created object (with its new `id`). Reply with a short confirmation, not the raw JSON.

## Act on an existing reminder (update / complete / move / delete)

These all need the reminder's `id`. **Always do this 3-step recipe — never guess an id:**

1. Run `reminders list` with the most specific filter/list that should contain it.
2. Find the one item whose `title` matches the user's description; take its `id`. If nothing matches, tell the user and stop. If two or more plausibly match, show them and ask which one.
3. Run exactly one of:

```
# Update — pass only the fields being changed
~/.local/bin/systemmcp reminder reminders update <id> [--title "..."] [--due <date>] [--notes "..."] [--priority <...>] [--completed | --no-completed] [--timezone <...>]

# Mark complete (one or more ids)
~/.local/bin/systemmcp reminder reminders complete <id> [<id> ...]

# Move to another list (use this for any list change — NOT update)
~/.local/bin/systemmcp reminder reminders move <id> --list "<name|id>"

# Delete (one or more ids)
~/.local/bin/systemmcp reminder reminders delete <id> [<id> ...]
```

## Manage reminder lists

```
~/.local/bin/systemmcp reminder lists list                              # all lists, with ids
~/.local/bin/systemmcp reminder lists create "<name>"                   # errors if the name already exists
~/.local/bin/systemmcp reminder lists rename "<existing name|id>" "<new name>"
~/.local/bin/systemmcp reminder lists delete "<name|id>"                # deletes the list AND its reminders
```

Only add `--force` to `create` if the user explicitly says to make a duplicate of an existing-name list.

## Behavior rules

- **Before any delete (reminders or lists), list the target and show it to the user first**, then delete by `id`. The same goes for completing or moving something the user named — confirm you found the right item.
- Change a reminder's list only with `move`, never `update`.
- Translate every natural-language date to an allowed form (see Dates) before passing it. Anchor relative phrases to the current date in the conversation.
- Don't paste raw JSON back. Reply with the count and the key facts in the user's language (e.g. "今日のリマインダーは3件: …").
