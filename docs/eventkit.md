# EventKit の文書化されていない制約

EventKit / reminderkit を触っていて踏んだ、公式ドキュメントに明記がない挙動・制約のメモ。
コードのコメントからもここを参照する。エラーコード（`reminderkit error -3002` など）は
原因が異なっても同じ値が返るため、現象から原因を切り分けた経緯も残す。

## 1. 場所アラーム付きリマインダーのリスト移動は 1 回の save では失敗する（確定）

**現象**: `EKStructuredLocation` 付きの `EKAlarm`（ジオフェンス）を持つ既存リマインダーの
`calendar` を別リストに付け替えて `store.save(_:commit:)` すると `reminderkit error -3002` で失敗する。

**確定した切り分け**:
- 新規作成（`EKReminder` を作って `calendar` + 場所アラームをセットし初回 save）は成功する。
- 場所アラームを持たないリマインダーのリスト移動は成功する。
- 「既に場所アラームを持つ」リマインダーの移動だけが失敗する。
- 場所アラームは、登録時のリスト（source）に紐づく。移動と同時にそのアラームを保持しようとすると弾かれる。

**対処**: 移動を `moveReminder(id:list:)` に分離し、2 段階 save で行う。
1. 場所アラームを detach（同等の新しい `EKAlarm` を退避用に複製）
2. リスト移動だけを save（commit）
3. 退避したアラームを付け直して再度 save（commit）= 移動先リストでジオフェンスを新規登録（新規作成の成功経路と同じ）

場所アラームが無ければ単純に 1 回 save、移動先が現在と同じなら no-op。
実装: `Sources/SystemMCPCore/Reminder/EventKitService+Reminders.swift` の `moveReminder` / `detachLocationAlarms`。

## 2. 共有リストへのリマインダー移動は EventKit では実質できない（実機確認済み）

**現象**: 共有リストへ `EKReminder.calendar` を付け替えて save すると `reminderkit error -3002` で失敗する。
場所アラームの有無に関係なく発生する（アラーム無しのリマインダーでも失敗を確認済み）。

**切り分け（ログ + 実機）**:
- 非共有（自分のアカウントの）リストへの移動は ID 指定で成功する。
- 共有リストへは、リスト名・リスト ID のどちらを指定しても -3002 で失敗する（名前解決の問題ではない）。
- 重要: 実機の `move_reminder` で出たメッセージは「同一 source」分岐だった
  （`this can happen when the destination is a shared list`）。つまり **共有リストは別アカウント
  ではなく、同一 iCloud source 内の共有カレンダー**。
  - そのため `origin.source` と `destination.source` の比較ではクロスアカウントとして検出できない。
  - `allowsContentModifications` も true（編集権はある）なので事前チェックも素通りする。
  - 結局「同一 source 内でも、共有カレンダーへの `.calendar` 付け替え（移動）だけは弾かれる」。
    検出手段が無く、save が失敗して初めて分かる。
- → 結論: **共有リストへのリマインダー「移動」は EventKit では実質不可能**。

**現在の対処**: `moveReminder` は 2 段構え。
1. まず in-place（`reminder.calendar` 付け替え）を試す。同一アカウント内の通常リストはこれで成功し、
   **id を保持・全フィールド無損失**。場所アラーム付きは項目 1 の 2 段階 save で処理。
2. EventKit が弾いたら（共有リスト等）`store.reset()` で未コミットの変更を破棄し、**delete+recreate**:
   移動先リストに同内容の新規リマインダーを作成 → 成功後に元を削除。**id は変わる**。
   安全のため「新規作成が成功してから元を削除」する（作成に失敗しても元データは失わない）。
- 移動先が `allowsContentModifications == false`（read-only。編集権の無い共有リスト等）なら最初に弾く。

実機で確認済み:
- in-place（`reminder.calendar` 付け替え）での共有リストへの移動は -3002 で失敗する。
- 一方、共有リストへの**新規作成（add）は通る**。よって delete+recreate に切り替えると
  共有リストへの移動が成立する（id は変わる）。`move_reminder` で実際に成功を確認。
- → 「共有リストへは移動（calendar 付け替え）は不可だが、作成は可能」が EventKit の挙動。
  項目 1 の場所アラームと同じく、move と add で挙動が異なる一例。

補足: `clone(_:)` で alarm（location / absolute / relative）を新規リマインダー用に複製する。
recreate で複写するのは title / notes / priority / due / start / completed / url / alarms。
繰り返しルール等スコープ外のフィールドは複写されない点に注意。

## 3. 時刻のアンカー: 既定は端末ローカルゾーンで固定、floating は明示的に opt-in

**背景**: EventKit ではイベント (`EKEvent`) とリマインダー (`EKReminder`) で時刻の持ち方が違う。

- **イベント**: `startDate`/`endDate` は絶対時刻（`Date`）+ `timeZone`（optional）。`timeZone` セット時は
  その一点を指す。カレンダーアプリで表示ゾーンを切り替えると、壁掛け時計の表示は動くが**順序は不変**。
  `timeZone == nil` の floating イベントもあり得る（どの地域でもその壁掛け時計時刻）。
- **リマインダー**: 期日は `dueDateComponents`（`DateComponents`）で持つ。`DateComponents.timeZone`
  が **nil なら floating**（タイムゾーン非依存の壁掛け時計時刻。デバイスの現在ゾーンでその時刻に発火）、
  **セットすれば fixed**（そのゾーンの絶対時刻に固定）。

**問題**: floating なリマインダーと絶対時刻のイベントを同じタイムライン上で並べると、
表示ゾーンを切り替えたときに**両者の前後関係がずれる**（floating 側だけ壁掛け時計に追従して動くため）。
MCP/LLM 経由だとこの差を取り違えやすい。floating は特殊なので、**省略時に暗黙で floating になる**のは罠。

**対処（入力側のアンカー方針）**: floating を**別フラグにせず、`timezone` という 1 つの引数の選択肢**として
表現する（`floating` は「ゾーン無し」というタイムゾーン指定の一種）。これで「ゾーン固定」と「floating」を
同時に要求でき得ない＝**矛盾が構造的に起きない**。Calendar の UI（タイムゾーン欄に "None"＝floating がある）とも揃う。
add/update の `timezone`（CLI `--timezone` / MCP `timezone`）の値:

- **省略** → **端末ローカルゾーン（`.current`）で固定**（絶対時刻）。「9:00」＝「今この端末のゾーンの 9:00」。既定。
- **ゾーン名（`America/New_York`, `EST` 等）** → そのゾーンで解釈・固定（順序が安定）。
- **`floating`（または `none`、大小無視）** → ゾーン無しの floating（`DueComponents.timeZone == nil` /
  `EKEvent.timeZone == nil`）。明示したときだけ floating になる。

実装は `TimeAnchor`（`local` / `floating` / `fixed(TimeZone)`）に集約。`parseAnchorOrThrow(_:)` が
`timezone` 文字列を `TimeAnchor` に解決し、`parseZone`（入力日時の解釈ゾーン。local/floating は `.current`）と
`dueZone`（リマインダーのアンカー。floating は nil）を提供。イベントは `applyAnchor` で適用し、`local` は
**EKEvent のゾーンを触らない**（新規は既定でローカル、更新は既存ゾーンを保持）、`floating` は nil、`fixed` はそのゾーン。
`ReminderResponse.timeZone` で現在の固定ゾーン（floating なら nil）、`floating: Bool` で floating を明示。
相対オフセット（`+1h` 等）は now 基準で解決されゾーン非依存なので、ゾーン固定時はその絶対時刻が固定される。

**JSON 出力の時刻表記**: 壁掛け時計が直接読めるよう、UTC の `Z` 固定はやめ、**意味に応じて形を変える**:

- **fixed（ゾーン指定）の期日・イベント** — そのゾーンの **UTC オフセット付き** ISO8601
  （`2026-06-15T20:08:00-07:00`）。絶対時刻なので、その offset で読めばよい。
- **floating（ゾーン無し）の期日・イベント** — **オフセット無し**の壁掛け時計（`2026-06-10T09:00:00`）。
  floating は「どの地域でもその壁掛け時計時刻に発火」する性質で offset の概念が無いため、付けると
  「固定された予定」に誤読され、LLM が他ゾーンへ変換しかねない。offset を**付けない**ことで
  「ゾーン非依存・変換するな」を表す。さらにレスポンスに **`floating: true`** を立てて明示する
  （`timeZone == nil` と等価だが、nil の見落としを防ぐため独立フィールドにした）。
- **`creationDate` 等のメタデータ** — 端末ローカル（`.current`）のオフセット付き。

これにより MCP/LLM が UTC→現地の変換を手計算する必要がなくなり、報告時刻の取り違えを防ぐ。
実装: アンカー付き日付は `ZonedDate`（`timeZone` 非 nil → `DateParsing.iso8601String`、nil → `floatingString`）、
メタデータは `jsonEncoder` の custom strategy（`.current` オフセット）。`floating` フラグは
`ReminderResponse`/`EventResponse` の init で `dueDateComponents?.timeZone == nil` /
`EKEvent.timeZone == nil` から立てる。

## 補足: 同名リストの曖昧さ

-3002 とは別問題だが関連して踏んだもの。リストを名前で解決する際、同名リストが複数あると
一意に決まらない。EventKit がエラーで弾く以前に、こちらの名前解決（`calendar(idOrName:entity:label:)`）が
先頭を黙って返すと誤動作の温床になる（解決失敗を「リストが無い」と誤読して重複リストを作る等）。

**対処**:
- 名前一致が複数なら `EventKitError.ambiguous`（候補 ID 付き）を投げ、先頭を勝手に選ばない。
- `createReminderList(name:force:)` は同名リストが既にあると既定でエラー（重複生成を防ぐ）。
  `force` 指定時のみ作成し、`force` はユーザーの明示的許可が前提（MCP の説明にも明記）。

## TCC / 検証についての注意

EventKit の実 CRUD には TCC 権限（Info.plist 埋め込み + コード署名 + 対話的な初回許可）が必要。
ヘッドレス/サンドボックスでは `notDetermined` のままで各操作が `accessDenied` を返すため、
ここに書いた -3002 系の挙動はユニットテストでは再現できない。署名済みバイナリを実機で動かして確認する。
