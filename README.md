# eventkitctl

macOS のカレンダー・リマインダーを **EventKit** 経由で操作する Swift 製ツール。
1つのバイナリで **CLI** としても **MCP サーバー** としても動き、Claude Desktop から
カレンダー/リマインダーを読み書きできる。

`mikakoivisto/reminders-mcp`(TS製ラッパー)と `openclaw/remindctl`(Swift CLI)を参考に、
CLI と MCP を1プロジェクトに統合したもの。

## 特徴

- リマインダー: 一覧(today/tomorrow/week/overdue/upcoming/completed/all・日付範囲)、追加・編集・完了・削除
- リマインダーリスト: 一覧・作成・リネーム・削除
- カレンダー: 一覧
- イベント: 期間指定の一覧、追加・編集・削除
- EventKit を直接利用するので iCloud 同期はそのまま機能する

> 繰り返し・アラーム・場所トリガーは現状スコープ外（将来対応）。

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
3. `.build/release/eventkitctl` の絶対パスを表示

Info.plist（権限の説明文）はリンク時にバイナリへ埋め込み済み
（`Package.swift` の `linkerSettings` 参照）。

Developer ID で署名したい場合:

```sh
make sign SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

## 権限の付与（初回のみ）

ターミナルから一度実行して、表示されるダイアログで許可する:

```sh
.build/release/eventkitctl status
# => {"events":"fullAccess","reminders":"fullAccess"} になればOK
```

許可後は System Settings → プライバシーとセキュリティ →
カレンダー / リマインダー に `eventkitctl` が現れる。

## CLI の使い方

すべて JSON を標準出力に返す。

```sh
# 認可状態
eventkitctl status

# リスト / カレンダー一覧
eventkitctl lists list
eventkitctl calendars list

# リマインダー
eventkitctl reminders list --filter today
eventkitctl reminders list --start 2026-06-08 --end 2026-06-15
eventkitctl reminders add --title "牛乳を買う" --due tomorrow --priority high --list "買い物"
eventkitctl reminders update <id> --completed
eventkitctl reminders complete <id> [<id>...]
eventkitctl reminders delete <id> [<id>...]

# リスト管理
eventkitctl lists create "仕事"
eventkitctl lists rename "仕事" "Work"
eventkitctl lists delete "Work"

# イベント
eventkitctl events list --start today --end 2026-06-30
eventkitctl events add --title "会議" --start "2026-06-10T10:00" --end "2026-06-10T11:00"
eventkitctl events update <id> --location "会議室A"
eventkitctl events delete <id>
```

日付は ISO8601（`2026-06-10` / `2026-06-10T10:00`）または
`today` / `tomorrow` / `yesterday` が使える。

## Claude Desktop への登録

`~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "eventkitctl": {
      "command": "/Users/mzp/ghq/github.com/mzp/eventkitctl/.build/release/eventkitctl",
      "args": ["serve"]
    }
  }
}
```

`command` は `make install` が表示する絶対パスに置き換える。Claude Desktop を再起動すると
「今日のリマインダー教えて」「明日10時に会議を入れて」などで使えるようになる。

> 先に `eventkitctl status` で権限を付与しておくこと。未許可だと各ツールは
> アクセスエラーを返す。

## ログ

ログは **stderr** と **ファイル**に出力する（stdout は CLI の結果 JSON / MCP プロトコル専用なので汚さない）。
環境変数で制御:

| 変数 | 説明 |
|---|---|
| `EVENTKITCTL_LOG` | レベル: `trace`/`debug`/`info`/`notice`/`warning`/`error`/`critical`（既定 `info`、各操作のパラメータは `debug`） |
| `EVENTKITCTL_LOG_FILE` | 出力先ファイル（`~` 展開可）。空文字でファイル出力オフ |

`serve`（MCP）では `EVENTKITCTL_LOG_FILE` 未指定でも **`~/Library/Logs/eventkitctl.log`** に出力する
（Claude Desktop から起動するとターミナルが無いため）。

```sh
# CLI でファイルにも出す
EVENTKITCTL_LOG=debug EVENTKITCTL_LOG_FILE=/tmp/ek.log ek reminders list --filter today

# MCP のログを追う
tail -f ~/Library/Logs/eventkitctl.log
```

Claude Desktop でレベルや出力先を変えたい場合は config に `env` を追加:

```json
{
  "mcpServers": {
    "eventkitctl": {
      "command": "/Users/mzp/ghq/github.com/mzp/eventkitctl/.build/release/eventkitctl",
      "args": ["serve"],
      "env": { "EVENTKITCTL_LOG": "debug" }
    }
  }
}
```

## 提供する MCP ツール

| ツール | 説明 |
|---|---|
| `get_status` | 認可状態 |
| `list_reminders` | リマインダー一覧（filter / 日付範囲 / list） |
| `add_reminder` / `update_reminder` | 追加 / 編集 |
| `complete_reminders` / `delete_reminders` | 完了 / 削除（複数可） |
| `list_reminder_lists` / `create_reminder_list` / `rename_reminder_list` / `delete_reminder_list` | リスト管理 |
| `list_calendars` | カレンダー一覧 |
| `list_events` | イベント一覧（期間） |
| `add_event` / `update_event` / `delete_events` | 追加 / 編集 / 削除 |

## 構成

```
Sources/AppCore/   EventKit ラッパー(actor) + Codable レスポンス型 + 日付パース
Sources/eventkitctl/    ArgumentParser の CLI + MCP serve
  Commands/             status / reminders / lists / events / calendars
  ToolDefinitions.swift MCP ツール定義とディスパッチ
  MCPServer.swift       serve サブコマンド
Resources/Info.plist    TCC 用 usage description（バイナリへ埋め込み）
```

CLI と MCP は同じ `EventStoreService`（actor）を共有し、ロジックを二重実装しない。
