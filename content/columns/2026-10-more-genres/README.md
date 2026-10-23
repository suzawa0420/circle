# 追加ジャンルの商品紹介記事15本

2026-10-23、通常の管理画面から作成・公開。既存記事と重複しない15本を追加。Amazonのみ、本文内に商品カード計94件を配置。

| 記事 | 公開URL | 商品数 |
| --- | --- | --- |
| 草野球の持ち物 | https://circle-book.com/columns/14 | 8 |
| ダンスの持ち物 | https://circle-book.com/columns/15 | 7 |
| 水泳の持ち物 | https://circle-book.com/columns/16 | 7 |
| モルックの主催者向け備品 | https://circle-book.com/columns/17 | 5 |
| 街歩きの持ち物 | https://circle-book.com/columns/18 | 7 |
| 料理会の持ち物 | https://circle-book.com/columns/19 | 5 |
| ボルダリングの持ち物 | https://circle-book.com/columns/20 | 5 |
| グループライドの用品 | https://circle-book.com/columns/21 | 8 |
| スキー・スノーボードの小物 | https://circle-book.com/columns/22 | 7 |
| キャンプの個人用品 | https://circle-book.com/columns/23 | 7 |
| バドミントンの主催者向け備品 | https://circle-book.com/columns/24 | 6 |
| バレーの主催者向け備品 | https://circle-book.com/columns/25 | 6 |
| フットサルの主催者向け備品 | https://circle-book.com/columns/26 | 6 |
| 卓球の主催者向け備品 | https://circle-book.com/columns/27 | 5 |
| 交流会の受付用品 | https://circle-book.com/columns/28 | 5 |

## 画像

新規15本のアイキャッチを、ChatGPTアプリ同梱のCodex 0.163.0-alpha.11.2による `codex exec` と組み込み `image_gen` で生成。すべて1536×1024 PNG。APIキーやImages APIの直接呼出しは使用していない。`images/` に成果物とプロンプト記録を保存。

草野球の生成プロンプト：晴れた日本の草野球場のベンチに、一般的なグラブ・軟式球・練習着・靴・バッグを並べた、人物・文字・ロゴなしの自然な編集記事向け写真。

2026-10-24、ユーザーによるChrome拡張機能のファイルURLアクセス有効化後、通常の管理画面から15枚すべてをアップロードして公開状態で保存。公開記事のアイキャッチとOGPのURL一致、一覧のサムネイル、商品カード94件の維持を確認。結果は `cover-checks.json` に記録。

## 確認

- 保存済みプレビューで全文の欠落0、見出し一致、商品カード94件・商品画像94件、未変換番号0を確認。
- 未ログインで15記事の一般公開、Amazon紹介タグ、noindexなしを確認。
- masterへの原稿・生成画像コミット `deba57b78` の本番デプロイとサイトマップ生成は成功（GitHub Actions 39973141110）。画像設定後の記録更新でも通常のデプロイを実行。
- 参加者向け9ジャンルの公開一覧で記事リンクを確認。主催者向け6記事は対象者・種目を設定し、既存の主催者向け導線の抽出対象となる。実在アカウントの興味設定は変更していない。
- 参考リンク集、固定価格・在庫・評価点・架空の使用体験は本文へ入れていない。商品リンクは検索結果で、画像が候補の一例であることをカードに記載。
- 商品情報の新規照合は `amazon-observations.json` に記録。既存記事の共通用品は確認済みデータを利用。
- 公開取消は通常の管理画面で下書きへ戻す。

## 編集用の公式確認資料

本文に参考リンク集は掲載せず、確認用にのみ記録。

- 野球：https://jpn.mizuno.com/baseball/dear-rookie/first-tools
- 水泳：https://jpn.mizuno.com/swim/basic
- モルック：https://molkky.jp/faq/
- モルックの構成：https://www.molkky.world/ja/buy-molkky
- チョークバッグ：https://www.petzl.co.jp/sport/sakab/
- ヘルメット：https://www.ogkkabuto.co.jp/bicycle/products/cycling/rect/rect.html
- 前照灯：https://www.cateye.com/jp/products/headlights/HL-EL085RC/
- シャトル：https://www.yonex.co.jp/lp/as-500/
- 卓球用品：https://www.butterfly.co.jp/products/table_equipment/ball_equipment/
- マグ：https://www.snowpeak.co.jp/products/MG/
- 保冷バッグ：https://www.thermos.jp/product/list/cooler.html
- 名札：https://www.kokuyo.com/stationery/category/other-officesupplies/nametag/13876/
