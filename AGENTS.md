# サークルブックの作業ルール

全体ルール `/Users/suzawa/.codex/rules/common.md` を適用する。

## 本番サーバーへのSSH接続

- このPCでは、保存済みのSSH設定 `circle-production` を使用し、原則としてブラウザ端末よりコマンドラインでの操作を優先する。
- 接続コマンドは `ssh circle-production`。単発の確認には `ssh -o BatchMode=yes circle-production '<確認コマンド>'` を使用できる。
- 接続先は Lightsail の `circle-book-web-server4`、ホスト `18.176.169.209`、ポート `22`、ユーザー `ec2-user`。アプリケーションは `/var/www/circle` にある。
- ローカルの設定は `~/.ssh/config`、認証には既存の `~/.ssh/id_rsa`、公開ホスト鍵の検証には `~/.ssh/circle_server4_known_hosts` を使用する。秘密鍵の内容は読み取ったり表示したりしない。
- ホスト鍵はAWSのブラウザSSH経由で照合済み。`StrictHostKeyChecking yes` を維持する。不一致が出た場合は検証を無効化せず、AWS管理画面から接続先と公開ホスト鍵を再確認する。
- この設定はserver4への接続用。server5への接続設定・公開鍵登録が済んでいるとは扱わない。
- SSH接続設定があることを、本番変更の包括的な許可とは扱わない。依頼に必要な確認・操作に限り、本番データの変更、デプロイ、再起動などはユーザーが明示的に依頼・許可した範囲だけで行う。
- 現行の構成とデプロイ手順は `ops/al2023/README.md` を確認する。READMEに残る旧Unicorn手順をそのまま本番で実行しない。

2026年10月16日、このPCから `ssh circle-production` でserver4の `ec2-user` への接続成功を確認済み。
