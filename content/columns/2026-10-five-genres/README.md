# 初参加向け・5ジャンルの商品紹介記事

2026-10-22、ユーザーの依頼により通常の管理画面から5記事を公開。Amazonのみ。アイキャッチは前回のユーザー希望に合わせて後回し。コード変更・コミット・プッシュ・デプロイなし。

| ジャンル | 記事URL | 商品数 |
| --- | --- | --- |
| フットサル | https://circle-book.com/columns/9 | 8 |
| テニス | https://circle-book.com/columns/10 | 8 |
| 卓球 | https://circle-book.com/columns/11 | 7 |
| ランニング | https://circle-book.com/columns/12 | 8 |
| ヨガ | https://circle-book.com/columns/13 | 6 |

## 内容と検証

- 各HTMLが本文原稿、articles.jsonが対象・要約・商品カードの情報。実際の入力はTrixの見出しボタンと商品挿入ボタンを使用。
- 商品の用途・仕様はresearch.jsonのメーカー公式で確認。新規画像はAmazonの画面上で照合し、配信URLを直接利用。画像の再アップロードなし。
- 参考リンク集、固定価格・評価点・架空の使用体験は本文に追加していない。Amazonへのリンクは対象商品の検索結果。
- draft-checks.json：本文の欠落0、商品番号の未変換0、見出し数と商品カード数・画像数、紹介タグを確認。
- public-checks.json：未ログインで5記事の一般公開を確認。
- placement-checks.json：各種目ページに該当記事へのリンクが表示されることを確認。
- 商品カードは本文内に配置。参加者向け・各種目を指定。実在する利用者の興味設定は変更していない。
- 公開を戻す場合は通常の管理画面で下書き保存する。


2026-10-23 update: generated hero images have been uploaded and published through the normal editor. See ../2026-10-generated-covers/ for the final images and verification records.
