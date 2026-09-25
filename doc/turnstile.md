# Turnstileによる新規登録保護

## 対象と動作

主催者・参加者・出展者のDevise新規登録POSTを対象とする。ログイン、アカウント更新、閲覧、healthは対象外。
既存のIPレート制限とhoneypotも維持する。国外一律遮断はしない。

登録画面でのみCloudflareの公式スクリプトを読み込む。Turbolinksの遷移・戻る操作ではウィジェットを作り直す。
検証は `https://challenges.cloudflare.com/turnstile/v0/siteverify` にHTTPSで送信する。
送信内容はウィジェットの秘密キーと検証トークンのみ。メール・パスワード・任意の訪問者IPパラメータは送らない。
ウィジェット自身は利用者のブラウザからCloudflareに接続するため、公開前にプライバシーポリシーとの整合も確認する。

`success == true` に加え、hostnameが `circle-book.com` または `www.circle-book.com`、actionが `registration` であることを必須にする。
トークン期限（5分）と再利用拒否はCloudflareの検証結果に従い、ローカルで成功をキャッシュしない。
失敗時は422、外部通信障害や設定不足は503でフォームを再表示する。入力済みメールは保持し、パスワードは消去する。
通信は接続2秒、読み書き3秒、全体6秒まで。自動リトライ・リダイレクト追従・プロキシ環境変数利用はしない。
本番でキーがない場合は新規登録だけ失敗する。保護が無言で無効になる動作はさせない。

## キーの配置

GitHub ActionsのRepository secretsに `TURNSTILE_SITE_KEY` と `TURNSTILE_SECRET_KEY` を保存する。
デプロイ開始前に存在・文字形式のみ判定し、未設定の場合はサーバー変更前に停止する。
SSH actionの環境変数転送（debug無効）で各サーバーへ渡し、`bin/install_turnstile_configuration` が
デプロイユーザーの `~/.config/circle/turnstile.json` に原子的に保存する。ディレクトリ0700、ファイル0600。
これはアプリが実行時に読むための専用ファイルであり、Git・アセット・ログには含めない。
デプロイユーザーとUnicorn起動ユーザーが同一であることをPIDの所有者で確認する。異なる場合は設定保存前に展開を止める。
秘密値や設定ファイルは操作担当エージェントが読み取らず、CLIの固定メッセージと終了状態のみ確認する。
GitHub Actions全ログ、環境変数一覧、設定ファイルの表示は行わない。`debug` / `set -x` は有効にしない。

UnicornはUSR2による入れ替え時、initializerが専用ファイルを再読込する。SSHセッションのexportが
既存プロセスに引き継がれることには依存しない。両サーバーへ同じ設定を導入する。
既存のRails credentialsや.envには触れない。開発・テストでは環境変数を使用し、両キーがない場合のみ無効。

## 検証

本番DB・本物のキー・外部通信を使わず実行できる：

```sh
bundle exec ruby test/security/registration_turnstile_test.rb
bundle exec ruby test/security/abuse_protection_test.rb
node test/security/registration_turnstile_js_test.js
```

APIのTLS・エンコード・タイムアウト、成功/不正/別ホスト/別action/期限切れ、障害時閉鎖、
コントローラでの作成阻止・入力保持・パスワード削除、キーの非公開、ファイル権限・原子的更新、
両サーバーへの設定順序、Turbolinks復元をダミーで検証する。
本番公開後は3つの登録画面のGET・ウィジェット表示、通常ページとログインの表示を確認する。
本番の実登録成功・Cloudflareでの検証成功は、所有者が正規の登録操作で確認する。
自動の本番アカウント作成や大量POST試験は行わない。

## 展開と戻し方

この変更でDBマイグレーション・追加Gem・DNS変更・有料契約は不要。
既存ワークフローのmigration確認とアセット生成は実行されるため、master先端の未適用migrationは展開前に別途確認する。
新規登録はCloudflare障害時に利用できなくなるが、閲覧・既存ユーザーのログインには影響させない。
展開前に最新origin/masterとの整合、デプロイユーザー、Secretsの存在を値を見ずに確認し、展開許可を得る。
通常はserver3、正常確認後server2の順に更新・再起動する。各サーバーの公開フォームGETで設定済みウィジェットが存在することも確認する。
展開途中は旧ワーカー/旧サーバーに認証なし登録が届く余地があるため、両台反映完了までは有効化完了と扱わない。
問題がある場合は今回のコミットをrevertして再デプロイする。既存のレート制限・honeypotは維持されるが、
Turnstileによる保護は外れる。設定ファイルは残っていても旧コードから参照されない。削除やキー交換は別途許可を得る。

公式仕様: https://developers.cloudflare.com/turnstile/get-started/server-side-validation/
