# スマホ向けの画像アップロード品質

## 原因と保存サイズ

共通の `ImageUploader` は原画像を長辺400pxへ縮小していた。
指定記事 `/circles/3603/blogs/159302` の公開ファイルは208×400pxで、
スマホでも横方向の画素が不足する。

| アップロード箇所 | 保存する長辺の上限 |
| --- | --- |
| Blog image_01〜04 | 400 → 1200px |
| Schedule top_image | 400 → 1200px |
| User pic_header / gallery_01〜04 | 400 → 1200px |
| Exhibition header_img / gallery_img_01〜04 | 400 → 1200px |
| ExhibitionGroupProfile header_img | 400 → 1200px |
| User pic_profile / Member・AdminUser image_profile / ExhibitionGroupProfile profile_img / EventAnswer icon | 400 → 640px |
| Column image | 1600 → 1200px |
| ChatMessage image | 既存2048pxを維持（暗号化・非公開） |

ユーザーの修正方針に合わせ、当初案の長辺1920pxから1200pxへ変更した。
スマホで約400 CSS pxの横長画像を表示する場合に最大約3倍の密度を確保する目安で、
1920px案に比べ最大画素数を約61%減らす。
縦長・横長とも縦横比を維持し、小画像は拡大保存しない。
縦長画像は長辺が上限に達するので、全画像で横1200pxを保証するものではない。
PCの大きな表示や極端な縦長画像より、スマホの見え方と容量を優先する。

向きを補正してから縮小し、JPEG品質85（当初案88）・プログレッシブ保存とする。
EXIFなどのメタデータを除去し、20MBの入力制限を維持する。
処理負荷のため60メガピクセル上限を追加した。
既存URL・拡張子・ストレージ設定は維持する。

## 既存画像

依頼に従い、既存画像の一括再処理・上書き・DB変更は行わない。
効果は新たなアップロードに限る。
一覧用の派生画像処理・サイズ・キャッシュ指紋も従来どおりとし、
既存派生画像の再生成を起こす変更は行わない。

## 検証と比較の再現

`bundle exec ruby test/uploaders/image_uploader_url_check.rb` は、
全マウントの上限、縦長、小画像の拡大防止、JPEG品質、向き補正の順序、
画素数制限、旧拡張子・URL互換性を検証する。

`bundle exec rails test test/integration/listing_images_test.rb` は、
専用ローカルPostgreSQLで画像配信、プリロード、キャッシュ、公開範囲、
フォールバック、ダウンロード制限、元ファイル保持を検証する。

`bundle exec ruby ops/image_quality_preview.rb` は外部通信・DBなしで
実際のアップロード処理を比較し、`output/image-quality/comparison.html`
（画像埋め込みの単独HTML）とmetrics.jsonを生成する。
比較には既存の1200×630pxのサイト画像を使う。
これをChromeのPC幅1440pxとiPhone 15相当（幅393px・DPR 3）で確認する。
これはアップロード処理の比較用で、本番記事を書き換えるものではない。

## 本番反映

新規マイグレーションはない。masterの通常デプロイを使用し、CI成功後に
server4・server5を順番にホット再起動する。既存デプロイ処理の適用済み
マイグレーション確認・サイトマップ更新は維持する。
問題時は今回の変更をrevertした新しいコミットを通常の経路でデプロイする。
