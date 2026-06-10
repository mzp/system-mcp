# systemmcp

macOS のリマインダー・カレンダーを **EventKit** 経由で操作する Swift 製ツール。
1 つのバイナリ **`systemmcp`** が 2 つのドメインをサブコマンドに分けて持つ:

- **`systemmcp reminder ...`** — リマインダーとリマインダーリスト
- **`systemmcp calendar ...`** — カレンダーとイベント

各ドメインは **CLI** としても **MCP サーバー**（`... serve`、stdio）としても動き、Claude Desktop から
それぞれを読み書きできる。共通ロジックとドメインロジックは `SystemMCPCore` ライブラリに集約している。

## 特徴

- **reminder**
  - リマインダー: 一覧(today/tomorrow/week/overdue/upcoming/completed/all・日付範囲)、追加・編集・完了・削除
  - リマインダーリスト: 一覧・作成・リネーム・削除
- **calendar**
  - カレンダー: 一覧
  - イベント: 期間指定の一覧、追加・編集・削除
- EventKit を直接利用するので iCloud 同期はそのまま機能する
- 操作した側の権限だけを要求する（`reminder` はリマインダー、`calendar` はカレンダー）

> 繰り返し・アラーム・場所トリガーは現状スコープ外（将来対応、`TODO.md` 参照）。

## 必要環境

- macOS 14 以降 / Swift 6 (Xcode 16+)

## ビルドと署名

```sh
# ビルド + ad-hoc 署名（個人利用ならこれでOK）
make install
```

`make install` は以下を行う:

1. `swift build -c release`
2. `codesign` でバイナリに署名（TCC が許可を記憶できるようにするため）
3. `.build/release/systemmcp` の絶対パスを表示

Info.plist（権限の説明文）はリンク時にバイナリへ埋め込み済み
（`Package.swift` の `linkerSettings` 参照。リマインダー + カレンダー両方の usage description）。

Developer ID で署名したい場合:

```sh
make sign SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

## テストと lint

```sh
make test       # ユニットテスト（swift test、TCC 権限不要）
make format     # swift format で整形
make lint       # swift format lint --strict
```

formatter/linter は Swift toolchain 同梱の `swift format` を使う（外部ツールのインストール不要）。
設定はルートの `.swift-format`。

## 権限の付与（初回のみ）

各ドメインをターミナルから一度実行して、表示されるダイアログで許可する:

```sh
.build/release/systemmcp reminder status
# => {"entity":"reminders","status":"fullAccess"} になればOK
.build/release/systemmcp calendar status
# => {"entity":"calendar","status":"fullAccess"} になればOK
```

許可後は System Settings → プライバシーとセキュリティ → リマインダー / カレンダー に `systemmcp` が現れる。

## CLI の使い方

すべて JSON を標準出力に返す。日付は ISO8601（`2026-06-10` / `2026-06-10T10:00`）または
`today` / `tomorrow` / `yesterday` が使える。

```sh
# --- reminder ---
systemmcp reminder status

# リスト
systemmcp reminder lists list
systemmcp reminder lists create "仕事"
systemmcp reminder lists rename "仕事" "Work"
systemmcp reminder lists delete "Work"

# リマインダー
systemmcp reminder reminders list --filter today
systemmcp reminder reminders list --start 2026-06-08 --end 2026-06-15
systemmcp reminder reminders add --title "牛乳を買う" --due tomorrow --priority high --list "買い物"
systemmcp reminder reminders update <id> --completed
systemmcp reminder reminders complete <id> [<id>...]
systemmcp reminder reminders delete <id> [<id>...]

# --- calendar ---
systemmcp calendar status

# カレンダー / イベント
systemmcp calendar calendars list
systemmcp calendar events list --start today --end 2026-06-30
systemmcp calendar events add --title "会議" --start "2026-06-10T10:00" --end "2026-06-10T11:00"
systemmcp calendar events update <id> --location "会議室A"
systemmcp calendar events delete <id>
```

## Claude Desktop への登録

各ドメインは独立した MCP サーバーなので、`mcpServers` に **2 エントリ**を登録する（同じ `systemmcp`
バイナリを別 args で呼ぶ）。`~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "apple-reminder": {
      "command": "/Users/mzp/ghq/github.com/mzp/system-mcp/.build/release/systemmcp",
      "args": ["reminder", "serve"]
    },
    "apple-calendar": {
      "command": "/Users/mzp/ghq/github.com/mzp/system-mcp/.build/release/systemmcp",
      "args": ["calendar", "serve"]
    }
  }
}
```

`command` は `make install` が表示する絶対パスに置き換える。Claude Desktop を再起動すると
「今日のリマインダー教えて」「明日10時に会議を入れて」などで使えるようになる。
不要な方だけ登録してもよい。

> 先に各ドメインの `status` で権限を付与しておくこと。未許可だと各ツールはアクセスエラーを返す。

## Hermes Agent への登録

[Hermes Agent](https://hermes-agent.nousresearch.com/) からも MCP サーバーとして使える。
コンパニオンアプリの設定（JSON）で `mcp_servers` に 2 エントリを追加する:

```json
{
  "mcp_servers": {
    "apple_reminder": {
      "command": "/Users/mzp/ghq/github.com/mzp/system-mcp/.build/release/systemmcp",
      "args": ["reminder", "serve"]
    },
    "apple_calendar": {
      "command": "/Users/mzp/ghq/github.com/mzp/system-mcp/.build/release/systemmcp",
      "args": ["calendar", "serve"]
    }
  }
}
```

`command` は `make install` が表示する絶対パスに置き換える。ツールは
`mcp_<サーバー名>_<ツール名>`（例: `mcp_apple_reminder_list_reminders`）として登録されるので、
サーバー名は snake_case にしておくと読みやすい。

- 設定後は Hermes を再起動する（セッション中に編集した場合は `/reload-mcp` で再読み込み）
- ログレベル等を変えたい場合は Claude Desktop と同様に各エントリへ `env`
  （`SYSTEM_MCP_LOG` / `SYSTEM_MCP_LOG_FILE`）を追加する
- 一部ツールだけ公開したい場合は `tools.include` / `tools.exclude` で絞り込める:

```json
{
  "mcp_servers": {
    "apple_reminder": {
      "command": "/Users/mzp/ghq/github.com/mzp/system-mcp/.build/release/systemmcp",
      "args": ["reminder", "serve"],
      "tools": { "include": ["get_status", "list_reminders", "add_reminder"] }
    }
  }
}
```

> こちらも先に各ドメインの `status` で権限を付与しておくこと。

## ログ

ログは **stderr** と **ファイル**に出力する（stdout は CLI の結果 JSON / MCP プロトコル専用なので汚さない）。
環境変数で制御:

| 変数 | 説明 |
|---|---|
| `SYSTEM_MCP_LOG` | レベル: `trace`/`debug`/`info`/`notice`/`warning`/`error`/`critical`（既定 `info`、各操作のパラメータは `debug`） |
| `SYSTEM_MCP_LOG_FILE` | 出力先ファイル（`~` 展開可）。空文字でファイル出力オフ |

`serve`（MCP）では `SYSTEM_MCP_LOG_FILE` 未指定でも **`~/Library/Logs/systemmcp.log`** に出力する
（Claude Desktop から起動するとターミナルが無いため）。

```sh
# CLI でファイルにも出す
SYSTEM_MCP_LOG=debug SYSTEM_MCP_LOG_FILE=/tmp/systemmcp.log systemmcp reminder reminders list --filter today

# MCP のログを追う
tail -f ~/Library/Logs/systemmcp.log
```

Claude Desktop でレベルや出力先を変えたい場合は各エントリに `env` を追加:

```json
{
  "mcpServers": {
    "apple-reminder": {
      "command": "/Users/mzp/ghq/github.com/mzp/system-mcp/.build/release/systemmcp",
      "args": ["reminder", "serve"],
      "env": { "SYSTEM_MCP_LOG": "debug" }
    }
  }
}
```

## 提供する MCP ツール

**`systemmcp reminder serve`**（MCP サーバー名 `apple-reminder`、10 ツール）

| ツール | 説明 |
|---|---|
| `get_status` | リマインダーの認可状態 |
| `list_reminders` | リマインダー一覧（filter / 日付範囲 / list） |
| `add_reminder` / `update_reminder` | 追加 / 編集 |
| `complete_reminders` / `delete_reminders` | 完了 / 削除（複数可） |
| `list_reminder_lists` / `create_reminder_list` / `rename_reminder_list` / `delete_reminder_list` | リスト管理 |

**`systemmcp calendar serve`**（MCP サーバー名 `apple-calendar`、6 ツール）

| ツール | 説明 |
|---|---|
| `get_status` | カレンダーの認可状態 |
| `list_calendars` | カレンダー一覧 |
| `list_events` | イベント一覧（期間） |
| `add_event` / `update_event` / `delete_events` | 追加 / 編集 / 削除 |

## 構成

```
Sources/SystemMCPCore/       ドメインロジックを含む共有ライブラリ
  EventKit/                  EventKit ラッパーの共有部
    EventKitService.swift    actor（認証・カレンダー検索）
    EventKitError.swift / StatusResponse.swift   エラー型・認可状態 DTO
  Reminder/                  reminder ドメイン
    EventKitService+Reminders.swift  reminder/list メソッド（extension）+ ReminderFilter
    ReminderResponse.swift / ReminderPriority.swift
  Calendar/                  event ドメイン
    EventKitService+Events.swift     event/calendar メソッド（extension）
    EventResponse.swift / CalendarResponse.swift
  DateParsing.swift          日付パース / JSON encoder・decoder
  Logging.swift / ProcessName.swift   ロガー・実行名
  MCPSupport.swift           MCP/CLI 共通ヘルパー（schema builder・JSON 出力など）
Sources/SystemMCP/             systemmcp（薄い CLI/MCP 層）
  Main.swift                 ルート systemmcp（subcommands: reminder / calendar）
  Reminder/                  ReminderCommand + status/reminders/lists/serve + ReminderMCP
  Calendar/                  CalendarCommand + status/events/calendars/serve + CalendarMCP
Resources/Info.plist         TCC usage description（リマインダー + カレンダー、埋め込み）
```

ドメインロジック（`EventKitService` の各メソッドとレスポンス型）は `SystemMCPCore` の
`Reminder/` `Calendar/` 配下に集約し、`SystemMCP` は CLI 引数と MCP ツールを Service につなぐだけの
薄い層に徹する。CLI と MCP は同じ Service を共有し、ロジックを二重実装しない。
