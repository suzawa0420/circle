# 2026-10-16 Core Web Vitals: 公開一覧の軽量化漏れ

## Search Consoleで確認した対象

2026-10-16 JST、ChromeのSearch Consoleで確認。レポート更新日は2026-10-14。
モバイル2,377 URL、PC1,278 URLが「LCP 2.5秒超」。不良URLはいずれも0。
件数は端末別のため、単純合算で固有URL数にはしない。

| 端末 | URLグループの代表パス | URL数 | グループLCP |
| --- | --- | ---: | ---: |
| モバイル | /badminton/kanagawa/14-yokohamashi/3220 | 657 | 2.8秒 |
| モバイル | /prefectures/tokyo/cities/13-shibuyaku | 582 | 2.9秒 |
| モバイル | /badminton/kumamoto/43-tamanashi | 488 | 3.8秒 |
| モバイル | /places/basketball/hokkaido/1-sapporoshi | 421 | 2.5秒 |
| モバイル | /prefectures/aichi/23-nagoyashi/tag/20 | 229 | 3.2秒 |
| PC | /badminton/kanagawa/14-yokohamashi/3220 | 657 | 3.2秒 |
| PC | /prefectures/tokyo/cities/13-shibuyaku | 582 | 2.5秒 |
| PC | /users/14881/schedules | 35 | 2.7秒 |
| PC | /users/10112 | 4 | 2.7秒 |

先頭の657件グループの代表URLはサークル詳細ではなく、旧UsersControllerの駅周辺一覧。
玉名市のURLは現行の/events/.../cities/...へ1回リダイレクトする。
サークル詳細や地域別一覧には既に軽量JS/CSS・WebP・先頭画像preloadがあるため、
今回のレポートを直ちに最新コードのLCPと見なさない。

## 原因と変更

匿名GETで駅周辺一覧と施設一覧がapplication.js、jquery-ui、Swiper、PhotoSwipeを
読み込むことを確認。駅別一覧が軽量表示判定から漏れ、施設一覧と公開カレンダーも
汎用バンドルを使っていた。

- 駅別一覧2種を既存の公開一覧経路に含める。表示用関連データを共有し、先頭画像をpreload。
  表示済みレコードの有無はany?で判定し、不要なCOUNTを避ける。
- 匿名の施設一覧・検索・公開活動カレンダーにpublic_directory.cssと遅延実行のpublic_listing.jsを使用。
  広告の起動は既存の画像描画後の処理を再利用し、GTMは既存のまま。
- CSSは既存のapplication.scssから必要なセレクターを保持。カレンダー状態の動的クラス、
  サークル上部ナビゲーション、保存リンクを保持する回帰テストを追加。
- これらのページではブラウザ標準の画像遅延読み込みを使う。
  公開詳細を含む軽量ページのロゴに既存のレスポンシブWebPを使い、
  カレンダー上部のプロフィール写真は小型派生画像にする。
- ログイン済み主催者・参加者等は従来のバンドルを維持。編集画面は対象外。

## 検証と限界

本番データ・秘密設定を使用せず、一時PostgreSQL16の合成データで
関連74 tests / 839 assertions、失敗・エラー0。
駅別・施設一覧、画像URL、公開/主催者カレンダー、既存一覧・詳細、runtimeを含む。
最終的な駅別COUNT省略後も6 tests / 95 assertions、失敗・エラー0。
新規テストはデプロイ前CIにも追加。

ChromeでPCの駅別一覧、390px幅の施設一覧・活動カレンダーを確認。
カレンダー月移動とモバイルメニューの開閉が動作。

変更前の実配信リソースを圧縮対応GETで取得した転送サイズ:
application.css 80,874 bytes、application.js 182,299 bytes。
既存public_listing.css 17,533 bytes、public_listing.js 6,568 bytes。
これらは個別ファイルのサイズであり、ページ全体の転送量やLCP測定値ではない。
新規public_directory.cssの実転送サイズはデプロイ後に確認する。

実ユーザーのLCPは未確定。Search Consoleの過去の集計は反映直後には更新されず、
修正検証と今後の実ユーザーデータによる確認が必要。

## デプロイ

masterへのcommit/push/本番デプロイはユーザーが本チャットで明示許可。
新規DBマイグレーションなし。既存workflowでCI、両サーバーのアセット生成、
適用済みmigration確認、Puma順次hot restart・readiness、サイトマップ更新を行う。
旧アセットは保持。問題時は今回のコミットをrevertして同じ手順でデプロイ。
本記録の作成時点ではデプロイ前であり、反映成否はActionsで別途確認する。
