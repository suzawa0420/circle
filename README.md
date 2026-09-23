# サークルブック

## 本番環境

### デプロイの仕組み

1. それぞれのサーバーにSSH接続
2. git pull origin masterを実行

という流れのみなので、変更内容によってはサーバー上で追加対応が必要

#### 新たにgemを追加した際

```
$ bundle install
```

#### DB変更した際

```
# 必ずmigration statusを確認してから実行
$ bundle exec rails db:migrate:status
$ bundle exec rails db:migrate
```

### コマンドまとめ

```
# ファイル設置箇所
$ cd /var/www/circle

# ステータス確認
$ sudo systemctl status unicorn
->active

# unicornサーバー起動
$ sudo systemctl start unicorn

# unicornサーバー停止
$ sudo systemctl stop unicorn

# ログ確認
## railsログ
$ tail /var/www/circle/log/unicorn.stdout.log

## unicornサーバーログ
$ tail /var/www/circle/log/unicorn.stderr.log
```

### 不正登録対策

追加契約なしの回数制限・Bot対策と検証手順は [運用メモ](doc/abuse_protection.md) を参照してください。
