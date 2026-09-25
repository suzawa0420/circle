# Cloudflareの通信保護への切り替え

## 準備済み（2026-09-25）

- お名前.comでネームサーバーを `indie.ns.cloudflare.com` と `vicente.ns.cloudflare.com` に変更済み。
- Cloudflare FreeでドメインとUniversal SSLがアクティブ。SSLモードはフル（厳格）。
- apexとwwwのCNAMEは既存Lightsailロードバランサーを参照。証明書検証2件、SES DKIM6件を維持。
- Web用DNSレコードは移行準備時点でDNSのみ。プロキシ有効化は下記の検証後。
- 下記WAFルールを無効状態で保存済み。ID: `e16ff36e619a46ce984282230d77d237`。
- Railsの信頼するプロキシにCloudflare公開IP範囲を追加するコードを用意。利用者のCFヘッダーを直接信用しない。

## 国外制限ルール

アクション: Block

```text
(http.host in {"circle-book.com" "www.circle-book.com"} and ip.src.country ne "JP" and not (cf.client.bot and http.request.method in {"GET" "HEAD"}))
```

国外・国不明の一般アクセスを遮断する。Cloudflareが検証したボットのGET/HEADのみ例外。海外滞在者、海外VPN、未検証の監視やプレビューにも影響する。User-Agentのみで例外を作らない。

## 本番適用の順序

1. 最新masterへIP判定の変更を反映。既存GitHub ActionsでServer3→Server2の順にデプロイ。DBスキーマの変更はないが、既存ワークフローのマイグレーション確認・アセット生成・Unicorn再起動は実行される。
2. 両サーバーのNginxで `proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;` を確認。Lightsail LBが実際の接続元を末尾へ追加することも前提。公開インターネット全体を信頼する設定は使わない。
3. apexとwwwのプロキシを有効化。これにより閲覧・ログイン・投稿のHTTPS通信はCloudflareで終端され、AWSへ再暗号化して送信される。
4. HTTPS応答、ログイン・登録画面、訪問者IPの判定、Cloudflare経由を確認。フォームHTMLにCache Everythingを適用しない。
5. WAFルールを有効化。国内閲覧が正常、国外の未検証アクセスが拒否されることを確認する。CF-IPCountryを自分で付けるテストは国判定の検証にならない。
6. 国内ボット対策は既存の登録Turnstile、フォーム検証、回数制限を維持。Bot Fight Modeは正規の自動連携への影響を確認したうえで有効化する。

プロキシ有効化ではCloudflareに認証・投稿通信を処理させるため、ブラウザ操作ルールに従って実行時の確認を取る。コードのpushは本番デプロイを起動するため、対象と影響を提示して承認を得る。

## 残る制約と直接アクセス

このRails設定はIP判定用であり、AWSへの直接アクセスを遮断するものではない。Lightsailロードバランサーやサーバーへ直接接続されるとWAFを迂回できる。Cloudflareだけを許可する構成、または専用のオリジン認証が別途必要。Cloudflareの公開IPだけの許可でも、他のCloudflare利用者からの経路を区別できない点に注意する。

ロードバランサーのヘルスチェック、証明書更新、管理接続を維持しながら対処する。未検証のファイアウォール変更や秘密ヘッダーの値の表示は行わない。

## 戻し方

国外制限による誤遮断はWAFルールを無効にする。通信全体の不具合はapex/wwwをDNSのみに戻す（DNSキャッシュ反映待ちがある）。コードの問題は当該コミットをrevertし同じデプロイ手順で戻す。旧AWS DNSゾーンは移行中に削除しない。

## 検証と仕様

`BUNDLE_PATH=/Users/suzawa/rails/circle/vendor/bundle bundle exec ruby test/security/run.rb`

IPv4/IPv6の別利用者のカウンター分離、中継IPが変わっても同一利用者を制限すること、偽のX-Forwarded-For先頭値やCF-Connecting-IPで制限を回避できないことを検証する。本番のネットワーク設定をこのテストだけで保証しない。

- IP範囲: https://www.cloudflare.com/ips/
- HTTP転送ヘッダー: https://developers.cloudflare.com/fundamentals/reference/http-headers/
- 国別ルール: https://developers.cloudflare.com/waf/custom-rules/use-cases/block-by-geographical-location/
