# CLAUDE.md

このリポジトリで作業する際のガイド。

## 概要

`eventkitctl` は macOS の **EventKit** でカレンダー・リマインダーを操作する Swift 製ツール。
1つのバイナリが **CLI**（`eventkitctl <subcommand>`）と **MCP サーバー**（`eventkitctl serve`、
stdio）を兼ねる。Claude Desktop から使うことを想定。

## アーキテクチャ

- **`Sources/AppCore/`** — ロジックの本体。CLI と MCP が共有するライブラリ。
  - `EventStoreService.swift` — `EKEventStore` を包む **actor**。権限要求と全 CRUD はここに集約。
    EventKit 型を外に漏らさず、Sendable な DTO だけを返す。
  - `Models.swift` — `ReminderDTO` / `EventDTO` / `CalendarDTO` 等の Codable DTO と
    EventKit→DTO 変換、`ReminderPriority`(none/low/medium/high ⇄ 0/9/5/1)。
  - `DateParsing.swift` — `EventKitDate.parse`（ISO8601 / `today`・`tomorrow`・`yesterday`）と
    共有 JSON encoder/decoder（ISO8601 日付）。
  - `Errors.swift` — `EventKitError`（`CustomStringConvertible` + `LocalizedError`）。
- **`Sources/eventkitctl/`** — 実行ファイル。
  - `Eventkitctl.swift` — ArgumentParser ルート、`Output.json`、グローバル `service`(actor 共有インスタンス)。
  - `Commands/` — `status` / `reminders` / `lists` / `events` / `calendars` サブコマンド。
  - `ToolDefinitions.swift` — MCP ツール定義(`allTools`)と `handleToolCall` ディスパッチ。
  - `MCPServer.swift` — `serve` サブコマンド（`Server` + `StdioTransport`）。
- **`Resources/Info.plist`** — TCC の usage description。**リンク時にバイナリへ埋め込む**
  (`Package.swift` の `linkerSettings` で `__TEXT,__info_plist` セクションに sectcreate)。

CLI と MCP は同じ `EventStoreService` を呼ぶだけで、ビジネスロジックを二重実装しない。
新しい操作を足すときは「Service にメソッド追加 → CLI サブコマンド追加 → `allTools` と
`handleToolCall` に追加」の順で 3 箇所を揃える。

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
.build/release/eventkitctl --help
.build/release/eventkitctl status

# MCP は stdio。initialize → tools/list の最小ハンドシェイクで確認:
printf '%s\n' \
'{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}' \
'{"jsonrpc":"2.0","method":"notifications/initialized"}' \
'{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
| .build/release/eventkitctl serve
```

## 重要な制約・注意

- **TCC 権限**: EventKit へのアクセスには、(1) Info.plist 埋め込み + (2) コード署名 が必須。
  さらに**対話的なターミナル/アプリから一度起動して許可ダイアログを承認**しないと
  `fullAccess` にならない。ヘッドレス/サンドボックス環境では `notDetermined` のままになり、
  各操作は `EventKitError.accessDenied` を返す（クラッシュはしない）。
- **MCP の stdout はプロトコル専用**。`serve` 中はログやデバッグ出力を **stdout に出さない**こと
  （`StdioTransport` は既定で NoOp ロガー。診断は stderr へ）。CLI 側の結果出力は stdout で問題ない。
- **Swift 6 strict concurrency**: `EKEventStore`・`EKReminder` などは非 Sendable。
  actor 境界やコンティニュエーションを跨いで EventKit オブジェクトを渡さない
  （`fetchReminders` のコールバック内で DTO に変換してから resume している）。
- 日付の追加対応は `DateParsing.swift` の 1 箇所に集約する。CLI と MCP は同じパーサを使う。

## スコープ外（将来）

繰り返し(EKRecurrenceRule)・アラーム(EKAlarm)・場所トリガー・export(CSV)・deep link。
追加する場合も「Service → CLI → MCP」の 3 点セットで実装する。
