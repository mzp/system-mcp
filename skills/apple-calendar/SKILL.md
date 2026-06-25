---
name: apple-calendar
description: View, add, update, and delete macOS Calendar events, and list calendars, via the systemmcp CLI. Always use this skill for anything about events, schedules, meetings, or calendars — including Japanese requests like 「予定追加して」「〇日に〇〇を入れて」「今週の予定見せて」「明日の予定は？」「ミーティング登録して」「予定を〇時に変更して」「予定キャンセルして」「カレンダー一覧出して」. Reminders / to-dos are handled by the separate apple-reminder skill.
---

# apple-calendar

Operate macOS Calendar by running the `systemmcp` CLI with the **terminal tool**. Run the host binary at the literal path below — do not invent any other path:

```
~/.local/bin/systemmcp calendar <subcommand> [options]
```

Follow the recipes below exactly. Use only the flags shown here; never invent flags, values, or subcommands.

## How to read a result

- **Success → JSON on stdout.** Shapes: `events list` and `calendars list` return a JSON **array**; `add` and `update` return one JSON **object**; `delete` returns `{"deleted":[...ids]}`.
- **Failure → a line starting with `Error:` on stderr, and stdout is empty.** When you see an `Error:` line (or stdout is not JSON), tell the user what failed and stop. Do not retry with guessed flags.
- The leading `... info systemmcp: ... authorization` log line on stderr is noise — ignore it.
- If `calendar status` is not `fullAccess`, say there is no access to Calendar and stop.

## Dates — read before passing any date

A date/time argument must be **exactly one of these forms**, or it is rejected with `Error: ... could not parse`:

- `today` / `tomorrow` / `yesterday` — each means **00:00 (start) of that day**, local time
- a signed relative offset from now: `+1h`, `+30m`, `-2d`, `+7d` (the sign is required; measured from the current moment)
- a full ISO8601 datetime you build from the conversation's current date, e.g. `2026-06-25T10:00:00`

**Never pass words like `next week`, `来週`, `週末`, `朝`.** Convert first.

## List events (start AND end are required)

```
~/.local/bin/systemmcp calendar events list --start <date> --end <date> [--calendar "<name|id>"] [--timezone <zone>]
```

Build the range from this table (using the current date in the conversation; assume today is `2026-06-25` in the ISO examples):

| User asks | Range |
|---|---|
| 今日の予定 / today | `--start today --end tomorrow` |
| 明日の予定 / tomorrow | `--start tomorrow --end 2026-06-27T00:00:00` (tomorrow 00:00 → the day after, 00:00) |
| 今週 / next 7 days | `--start today --end +7d` |
| 今後3日 / next 3 days | `--start today --end +3d` |
| ある特定の日 (e.g. 6/30) | `--start 2026-06-30T00:00:00 --end 2026-07-01T00:00:00` |

Rule of thumb: for a single specific day, set `--start` to that day at `T00:00:00` and `--end` to the **next** day at `T00:00:00`. Each returned event carries an `id` (eventIdentifier — note it contains a colon, so always pass it quoted).

## Add an event

```
~/.local/bin/systemmcp calendar events add --title "<title>" --start <date> --end <date> [--calendar "<name|id>"] [--all-day] [--notes "<notes>"] [--location "<place>"] [--url "<url>"] [--timezone <zone>]
```

- `--start` and `--end` are **required**. If the user gives only a start time, set `--end` to one hour later (build both as ISO datetimes from the current date), or ask if unsure.
- `--all-day` for a full-day event (still pass `--start`/`--end` as the day(s)).
- Omit `--calendar` to use the system default calendar. Only pass `--calendar` if the user names one; confirm it is writable first via `calendars list` (`allowsModifications: true`).
- `--location` is geocoded to a map pin when resolvable; otherwise it's kept as text.

Example — "dentist tomorrow 10–11am" (today = 2026-06-25):
```
~/.local/bin/systemmcp calendar events add --title "歯医者" --start "2026-06-26T10:00:00" --end "2026-06-26T11:00:00"
```
Returns the created object (with its `id`, `calendar`, resolved `startDate`/`endDate`, `timeZone`). Reply with a short confirmation, not the raw JSON.

## Act on an existing event (update / delete)

These need the event's `id`. **Always do this 3-step recipe — never guess an id:**

1. Run `events list` over a range that contains the event.
2. Find the one item whose `title`/time matches the user's description; take its `id`. If nothing matches, tell the user and stop. If two or more plausibly match, show them and ask which one.
3. Run exactly one of:

```
# Update — pass only the fields being changed. Passing --calendar moves it to another calendar.
~/.local/bin/systemmcp calendar events update "<id>" [--title "..."] [--start <date>] [--end <date>] [--calendar "..."] [--all-day | --no-all-day] [--notes "..."] [--location "..."] [--url "..."] [--timezone <...>]

# Delete (one or more ids; quote each because ids contain a colon)
~/.local/bin/systemmcp calendar events delete "<id>" ["<id>" ...]
```

## List calendars

```
~/.local/bin/systemmcp calendar calendars list      # all calendars, with id, color, allowsModifications
```
Calendars with `allowsModifications: false` (birthdays, holidays) cannot take new events — never add to those. Use this to pick or confirm a writable target.

## Behavior rules

- **Before any delete, list the event and show it to the user first**, then delete by `id`. Same for editing an event the user named — confirm you found the right one.
- Always give both `--start` and `--end`. When end is unspecified, default to start + 1 hour.
- Translate every natural-language date/time to an allowed form (see Dates), anchored to the current date in the conversation; treat an ambiguous zone as local.
- Don't paste raw JSON back. Reply with the count and the key facts in the user's language (e.g. "明日の予定は2件: 10時 歯医者、…").
