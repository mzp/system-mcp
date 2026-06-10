# TODO

EventKit では実現できるが、まだ未対応の機能。実装するときは原則、該当ドメイン
（リマインダー系は `systemmcp reminder`、イベント系は `systemmcp calendar`）で
**「`SystemMCPCore` の `EventKitService` extension にメソッド/引数追加 → CLI サブコマンド →
`ReminderMCP`/`CalendarMCP` の `tools` と `handle`」** の3点セットで揃える（CLAUDE.md 参照）。
日付パースの拡張は `SystemMCPCore/DateParsing.swift` に集約。

## 優先度: 高（ユーザー要望）

- [ ] **繰り返し (recurrence)** — `EKRecurrenceRule`
  - daily / weekly / monthly / yearly、interval、曜日指定、終了条件（回数 or 日付）。
  - `EKEvent.addRecurrenceRule(_:)` / `EKReminder.addRecurrenceRule(_:)`。
  - 編集・削除時の **span** に注意: `.thisEvent` か `.futureEvents` を引数で選べるように
    （今は固定 `.thisEvent`）。繰り返しの自然言語パース（"every weekday" 等）は別途検討。
- [ ] **アラーム (alarm)** — `EKAlarm`
  - 相対オフセット (`EKAlarm(relativeOffset:)`、例: 開始15分前) と絶対時刻 (`EKAlarm(absoluteDate:)`)。
  - イベント・リマインダー両対応 (`addAlarm(_:)`)。複数アラーム可。
- [x] **場所トリガー (location trigger)** — `EKStructuredLocation` + `EKAlarm`
  - 実装済み: `add_reminder` / `update_reminder` の `location`（住所/地名 → `Geocoder` で座標解決、
    解決不能はエラー）+ `proximity`（enter/leave、デフォルト enter）+ `radius`（メートル、省略時システム既定）。
  - update で location 指定時は既存の場所アラームを置き換える。**場所トリガーの解除**は未対応（将来）。

## 優先度: 中

- [ ] **イベントの追加属性**
  - [ ] タイムゾーン (`EKEvent.timeZone`)
  - [ ] 公開/予定あり状態 (`EKEvent.availability`: busy/free/tentative)
  - [ ] 出席者の **読み取り** (`EKEvent.attendees` / `EKParticipant`)
        ※招待の送信・出席者追加は EventKit の公開APIでは不可。
- [ ] **リマインダーの開始日** (`EKReminder.startDateComponents`) — 今は due のみ対応。
- [ ] **カレンダーの作成/リネーム/削除（イベント側）** — 今はリマインダーリストのみ。
      `EKCalendar(for: .event, ...)` + `saveCalendar`。

## 優先度: 低 / 周辺機能

- [ ] **export** — CSV / JSON ファイル出力（remindctl 参考）。
- [ ] **deep link** — `x-apple-reminderkit://` / `ical://` でアプリを開く `link` / `open`。
- [ ] **検索コマンド** — タイトル/メモ/URL 横断検索 (`search`)。
- [ ] **完了日範囲フィルタ** — `predicateForCompletedReminders(withCompletionDateStarting:ending:)` を活用。

## EventKit の公開APIでは不可（参考・対応しない）

- リマインダーの **タグ / スマートリスト / セクション**（公開API無し）。
- 添付ファイル。
- イベントへの出席者追加・招待送信。
