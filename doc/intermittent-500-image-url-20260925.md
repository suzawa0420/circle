# 画像未登録時の断続的500修正（2026-09-25）

## 原因と根拠

- 公開サイト8回の読み取り確認のうち4回が500。
- サーバー直接確認ではServer3のトップ・検索が500、Server2は200。
- Server3の直近ログを限定集計すると `ActionView::Template::Error` と
  `wrong number of arguments` が各180件。呼び出し箇所は
  `app/uploaders/image_uploader.rb:32` と `:81`。
- 画像URLキャッシュ更新の変更で `url(options = {})` が引数なしの呼び出しにも
  空ハッシュを親へ渡し、CarrierWaveから引数なし定義の `default_url` に渡って例外となった。
- 本番デプロイがServer3の再起動検証で停止し、サーバー間の反映差が残っていた。

## 修正

- `url(*args)` で呼び出し元の引数をそのまま転送。
- `default_url(*_args)` でCarrierWaveのオプション引数を受け付ける。
- アップロード済み画像の `v=updated_at` によるキャッシュ更新は維持。
- DB・認証情報・S3に接続しない回帰テストを追加し、本番の各Unicorn再起動前にも実行。

## テスト

- 修正前：6テスト中3件が本番と同じ引数エラーで失敗。
- 修正後：6テスト・10アサーション成功。
- 画像なし、明示オプション、画像あり、既存クエリ付きURL、時刻未設定、バージョンを検証。
- ローカル実行：`bundle exec ruby test/uploaders/image_uploader_url_check.rb`

## 反映・復旧確認

masterへの通常pushで既存ワークフローを起動し、Server3→Server2の順で反映する。
両サーバーへの直接GETとロードバランサー経由の複数ページGETで200を確認する。
DBマイグレーション・データ変更・DNS変更は今回の修正には含まない。
