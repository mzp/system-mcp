# CLAUDE.md

このリポジトリで作業する際のガイド。

## 概要

このリポジトリは 1 つの Swift パッケージ（モノレポ）から **1 つのバイナリ `systemmcp`** をビルドする。
`systemmcp` は 2 つのドメインをサブコマンドに分けて持つ:

- **`systemmcp reminder ...`** — リマインダー / リマインダーリスト
- **`systemmcp calendar ...`** — カレンダー / イベント

各ドメインが **CLI**（`systemmcp reminder reminders list` 等）と **MCP サーバー**
（`systemmcp reminder serve` / `systemmcp calendar serve`、stdio）を兼ねる。Claude Desktop からは
2 つの MCP サーバー（`apple-reminder` / `apple-calendar`）として登録する。共通ロジックと
ドメインロジックは `SystemMCPCore` ライブラリに集約している。

## アーキテクチャ

2 ターゲット構成（`Package.swift`）。**ドメインロジックは共有ライブラリ `SystemMCPCore` に集約**し、
executable `SystemMCP` は CLI/MCP の薄い presentation 層に徹する。

- **`Sources/SystemMCPCore/`** — ドメインロジックを含む共有ライブラリ。`EventKit/`・`Reminder/`・
  `Calendar/` サブディレクトリ + ルート直下のドメイン非依存ヘルパー（同一ターゲット）。
  - `EventKit/` — EventKit ラッパーの共有部。
    - `EventKitService.swift` — `EKEventStore` を包む **actor** の**共有部分**。権限
      （`requestAccess(to:)` / `ensureAccess(to:label:)` / `authorizationStatus(for:)`）と
      カレンダー検索（`calendar(idOrName:entity:label:)`）。`store` 等は `package`、
      ドメインメソッドは同一モジュール内の `extension` から `public` で生やす。EventKit 型を外に漏らさない。
    - `EventKitError.swift` — `EventKitError`。`accessDenied` の文言は実行バイナリ名（`executableName()`）から生成。
    - `StatusResponse.swift` — 認可状態 DTO（`authorizationStatus`/`requestAccess` の戻り値、単一エンティティ）。
  - `Reminder/` — reminder ドメイン。
    - `EventKitService+Reminders.swift` — `extension EventKitService` に reminder/list の CRUD（`public`）と `ReminderFilter`。
    - `ReminderResponse.swift` — `ReminderResponse` + EK 変換。
    - `ReminderPriority.swift` — `ReminderPriority`(none/low/medium/high ⇄ 0/1/5/9)。
  - `Calendar/` — event ドメイン。
    - `EventKitService+Events.swift` — `extension EventKitService` に event/calendar の CRUD（`public`）。
    - `EventResponse.swift` — `EventResponse` + EK 変換。
    - `CalendarResponse.swift` — カレンダー / リマインダーリスト両用のレスポンス型（`listCalendars` と `listReminderLists` が返す）。
  - ルート直下（ドメイン非依存）:
    - `DateParsing.swift` — `DateParsing.parse`（ISO8601 / `today`・`tomorrow`・`yesterday`）と共有 JSON encoder/decoder。
    - `Logging.swift` — 共有ロガー `log`。**stderr + 任意でファイル**に出力（stdout には絶対出さない）。
      ラベルと `serve` 時のデフォルトログファイルは**実行バイナリ名由来**（`~/Library/Logs/systemmcp.log`）。
      `SYSTEM_MCP_LOG`(レベル) / `SYSTEM_MCP_LOG_FILE`(出力先) で上書き可。
    - `ProcessName.swift` — `executableName()`（`CommandLine.arguments[0]` の basename）。
    - `MCPSupport.swift` — MCP/CLI ヘルパー（JSON Schema builder `object/string/bool/stringArray`、
      `jsonResult/errorResult/missing`、引数アクセサ、`Output.json`、`parseDateOrThrow`）。
- **`Sources/SystemMCP/`** — `systemmcp` 実行ファイル（薄い CLI/MCP 層）。
  - `Main.swift` — `@main struct SystemMCPCommand`、commandName `systemmcp`、subcommands `reminder` / `calendar`、
    グローバル `service`（両ドメイン共用の単一 actor インスタンス）。
  - `Reminder/` — `ReminderCommand`（`reminder` 親）/ `ReminderStatusCommand` / `RemindersCommand`
    （`resolveFilter` も）/ `ListsCommand` / `ReminderServeCommand` / `ReminderMCP`（`tools` + `handle`、10 個）。
  - `Calendar/` — `CalendarCommand`（`calendar` 親）/ `CalendarStatusCommand` / `EventsCommand` /
    `CalendarsCommand` / `CalendarServeCommand` / `CalendarMCP`（`tools` + `handle`、6 個）。
  - 型名の衝突を避けるため、ドメインごとに名前空間を分ける（`status`/`serve` は別型、MCP は enum `ReminderMCP`/`CalendarMCP`）。
- **`Resources/Info.plist`** — TCC usage description（リマインダー + カレンダー両方、bundle id `jp.mzp.systemmcp`）。
  **リンク時にバイナリへ埋め込む**（`SystemMCP` の `linkerSettings` で `__TEXT,__info_plist` に sectcreate）。

CLI と MCP は同じ `EventKitService` を呼ぶだけで、ビジネスロジックを二重実装しない。
**新しい操作を足すときは、該当ドメインで「`SystemMCPCore` の `Reminder/`・`Calendar/` 配下に
`EventKitService` の extension メソッド（+ 必要ならレスポンス型）を追加 → `SystemMCP` 側で CLI サブコマンド
追加 → `ReminderMCP`/`CalendarMCP` の `tools` と `handle` に追加」の順で揃える。** 共通の汎用ヘルパーや型は
`SystemMCPCore` ルート直下に置く。

## ビルド・実行

```sh
swift build                     # デバッグビルド
make release                    # リリースビルド
make sign                       # release + ad-hoc 署名
make install                    # release + 署名 + 絶対パス表示
make sign SIGN_IDENTITY="Developer ID Application: ..."   # Developer ID 署名
```

CLI/MCP の動作確認:

```sh
.build/release/systemmcp --help
.build/release/systemmcp reminder status
.build/release/systemmcp calendar status

# MCP は stdio。initialize → tools/list の最小ハンドシェイクで確認（calendar も同様）:
printf '%s\n' \
'{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}' \
'{"jsonrpc":"2.0","method":"notifications/initialized"}' \
'{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
| .build/release/systemmcp reminder serve
```

## 重要な制約・注意

- **TCC 権限**: EventKit へのアクセスには、(1) Info.plist 埋め込み + (2) コード署名 が必須。
  さらに**対話的なターミナル/アプリから一度起動して許可ダイアログを承認**しないと
  `fullAccess` にならない。ヘッドレス/サンドボックス環境では `notDetermined` のままになり、
  各操作は `EventKitError.accessDenied` を返す（クラッシュはしない）。`systemmcp reminder status` で
  リマインダー権限、`systemmcp calendar status` でカレンダー権限を要求する（必要な側だけ要求される）。
- **MCP の stdout はプロトコル専用**。`serve` 中はログやデバッグ出力を **stdout に出さない**こと。
  ロガー(`log`)は stderr + ファイルのみに出力し、`StdioTransport` にも同じ `log` を渡している。
  CLI 側の結果出力は stdout で問題ない。
- **Swift 6 strict concurrency**: `EKEventStore`・`EKReminder` などは非 Sendable。
  actor 境界やコンティニュエーションを跨いで EventKit オブジェクトを渡さない
  （`fetchReminders` のコールバック内で response 型に変換してから resume している）。
- `EventKitService` の共有部とドメイン extension はどちらも `SystemMCPCore`（同一モジュール）にある。
  `store` 等は `package`、`SystemMCP` から呼ぶドメインメソッドは `public`。
- 日付の追加対応は `SystemMCPCore/DateParsing.swift` の 1 箇所に集約する。CLI と MCP は同じパーサを使う。

## スコープ外（将来）

繰り返し(EKRecurrenceRule)・アラーム(EKAlarm)・場所トリガー・export(CSV)・deep link（`TODO.md` 参照）。
追加する場合も該当ドメインで「Service の extension → CLI → MCP」の 3 点セットで実装する。
