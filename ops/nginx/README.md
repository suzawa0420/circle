# Cloudflareオリジン制限（2026-09-25）

## 現在の本番状態

- Server2/Server3とも、Lightsailの公開TCP80許可をIPv4/IPv6両方で削除。SSHは変更なし。LBのプライベート通信は維持。
- 両サーバーに `/etc/nginx/conf.d/00-circle-origin-guard.conf` を配置。
- `/etc/nginx/conf.d/rails.conf` の2つのserverブロックから `/etc/nginx/circle-origin-guard-server.inc` をinclude。
- **本番のserver.incは現在空。LB経由の完全遮断は無効。** このリポジトリのserver.incは、DNS移行完了後に適用する有効化用の内容。
- 元のrails.confは各サーバーの `/etc/nginx/rails.conf.before-origin-guard` にrootのみ読める権限で保存。
- アプリ変更、DB変更、Unicorn再起動なし。Nginxのreloadのみ。

## 有効化を待つ理由

初回適用時にChromeの正規登録画面が403になり、直ちに両サーバーのserver.incを空にしてreload、ログイン画面の復旧を確認した。

調査で、Chromeの `/cdn-cgi/trace` がCloudflareの応答ではなく、AWSのDNSも旧LBのIPを返していた。自分の確認GETを既存アクセスログで集計すると、転送ヘッダーは1ホップでCloudflare外だった。DNS移行前の経路が残っている。

一方、Cloudflareの公開IPをcurl --resolveで指定したHTTPSの確認は200、同じ確認GETの転送ヘッダーは2ホップで末尾がCloudflare範囲だった。新経路は正常だが、旧経路も一般ユーザーが利用している段階で完全遮断しない。

## 有効化前の条件

1. 国内ブラウザ・AWS・複数のDNSリゾルバーで新しいCloudflare経路へ切り替わったことを確認。時間経過だけで判断しない。
2. LBの送信元が172.26.0.0/16、X-Forwarded-Forが追記方式であることを再確認。その他のプロキシ経路が増えた場合は設計を見直す。
3. 両サーバーの構文検証と隔離テストを実行。Server3から段階適用し、Cloudflare経由HTTPS、直接LB接続、偽のXFF、LBヘルスチェック、ローカルデプロイ確認をそれぞれ検証。
4. 正規通信が失敗したらserver.incを空にし、nginx -t成功後systemctl reload nginx。公開IPへのHTTPを戻す必要はない。

## 判定

geoのproxyはLightsail私設ネットワークだけを信頼する。**proxy_recursiveは設定しない**（既定で非再帰）。AWSが末尾に付加した直前接続元がCloudflareの公式IP範囲にあり、Hostがcircle-book.comまたはwwwである場合のみ通常通信を許可する。訪問者のCF-Connecting-IPやXFF先頭値は認証に使用しない。

LB内部からのGET/HEAD `/health` はXFFなしの場合に限り許可する。外部からの同一URLはLBがXFFを付加するので例外にならない。ローカル127.0.0.1/::1は既存デプロイ確認のため維持。

これはCloudflareネットワークの識別であり、自分のCloudflareゾーンを暗号学的に認証するものではない。共有ネットワークからの経路まで区別する強化には、専用オリジン認証またはTunnel等を別途設計する。

## 検証記録

Server3の既存Nginxを使い、127.0.0.1:18089の独立プロセスで10ケース成功：CF IPv4/IPv6、偽XFF先頭、XFFなし、別Host、LBヘルス、外部ヘルス、クエリ付きヘルス、POSTヘルス、不正IP。実サイト・DBへテスト投稿はしていない。

公開診断エンドポイント案は自動承認レビューで拒否され、作成しなかった。既存ログから自分の確認GETだけを対象とした件数・ホップ数・Cloudflare範囲内外の集計で代替し、IPやログ本文は出力していない。

## 既存スパム

管理画面 `/super_admin/circles` はマスター管理者ログインが必要。現在はログイン待ち。既存の口コミ・アカウント削除は物理削除で、復元可能な隔離機能はない。対象の公開内容と関連データを確認し、具体的な対象・影響を提示してから不可逆な削除の承認を得る。本番DBの直接更新や自動一括削除は行わない。

## 公式仕様

- https://docs.aws.amazon.com/lightsail/latest/userguide/understanding-firewall-and-port-mappings-in-amazon-lightsail.html
- https://nginx.org/en/docs/http/ngx_http_geo_module.html
- https://www.cloudflare.com/ips/
