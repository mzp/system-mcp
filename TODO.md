# TODO

EventKit では実現できるが、まだ未対応の機能。実装するときは原則
**「Service にメソッド/引数追加 → CLI サブコマンド → `allTools` と `handleToolCall`」**
の3点セットで揃える（CLAUDE.md 参照）。日付パースの拡張は `DateParsing.swift` に集約。

## 優先度: 高（ユーザー要望）

- [ ] **繰り返し (recurrence)** — `EKRecurrenceRule`
  - daily / weekly / monthly / yearly、interval、曜日指定、終了条件（回数 or 日付）。
  - `EKEvent.addRecurrenceRule(_:)` / `EKReminder.addRecurrenceRule(_:)`。
  - 編集・削除時の **span** に注意: `.thisEvent` か `.futureEvents` を引数で選べるように
    （今は固定 `.thisEvent`）。繰り返しの自然言語パース（"every weekday" 等）は別途検討。
- [ ] **アラーム (alarm)** — `EKAlarm`
  - 相対オフセット (`EKAlarm(relativeOffset:)`、例: 開始15分前) と絶対時刻 (`EKAlarm(absoluteDate:)`)。
  - イベント・リマインダー両対応 (`addAlarm(_:)`)。複数アラーム可。
- [ ] **場所トリガー (location trigger)** — `EKStructuredLocation` + `EKAlarm`
  - リマインダーの位置ベース通知。`alarm.structuredLocation` に座標 + `radius`、
    `alarm.proximity` = `.enter` / `.leave`。
  - 緯度経度（または地名→ジオコーディング）と半径を受け取る引数設計が必要。

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
