# 2026-09-25 Turnstile / 対戦募集リリース確認

## レビュー結果

基準: origin/master `5f24d8b5e`。既存のローカルmasterの7コミットはgit cherryで全て同等パッチが反映済み。
ヘッダー・iPhone入力ズーム・お問い合わせ先・権限修正・依存ロックの既存変更は基準ブランチから維持する。

今回追加:
- 主催者・参加者・出展者のTurnstile表示とサーバー検証、2台への設定導入、ローカル登録フォーム確認。
- MatchesControllerの関連事前読込とユーザーID条件のサブクエリ化。表示条件・順序・ページングを保持。

元の作業ディレクトリから反映しない差分（削除せず保管）:
- Userのupcoming_schedules全件preloadと一覧ビュー: 現行のCircleListingDataによる上限付き取得を取り消すため。
- schedulesビューのname_schedules全件preload: COUNTの代わりに参加回答全件を実体化し、メモリ増加の上限が未検証。
- tagsのRuby数値ソート: 既存の文字列順序・NULL順序と異なるため。
- db/schema.rbとモデル/fixture/testの自動注釈: bigint→integer等、実際のmigrationに対応しないローカルDB差分。
- 新規matchesインデックスmigration: 実際の実行計画・重複状況を未確認で、このリリースには不要。
- Unicorn 8→4ワーカー: 処理能力変更は別途負荷計測が必要。
- healthルート置換: 監視の成功判定が変わるため、今回の登録対策とは分離。
- slow_request_logging旧案: 現行errorレベルの実装をwarnへ戻すと本番ログレベルで計測が消える。
- README注意書き削除: 本番上で直接コミットしないという注意を残す。
- output/、.playwright-cli/: 生成物・画面記録・ログであり、本番コードには含めない。
- home関連事前読込は現行ブランチに同等実装済み。プロフィールの関連参照置換は関連ロード検証と合わせて別途扱う。

## ローカル検証

Ruby 2.7.6 / Rails 6.0.5.1の既存依存で実施。Rails本体は起動せず、本番DB・キーは使用しない。
- Turnstile: 17 tests / 147 assertions
- 既存不正登録対策: 10 tests / 217 assertions
- Unicorn再起動待機: 4 tests / 17 assertions
- 対戦募集と既存一覧: 専用一時PostgreSQLで7 tests / 245 assertions
- JavaScript: 読み込み、エラー、期限切れ、Turbolinks復元、重複初期化
- git diff --check

本番では新規アカウントを自動作成しない。実登録成功の最終確認は所有者の操作で行う。
本番の実行結果はリリース後に報告する。ロールバックは今回のコミットをrevertして再展開。
