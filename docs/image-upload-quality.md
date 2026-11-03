# 画像アップロード品質の改善

## 原因と変更

共通の `ImageUploader` が原画像そのものを長辺400pxへ縮小していた。
指定記事 `/circles/3603/blogs/159302` の先頭画像は公開ファイルを確認すると
208×400px（29,028 bytes）。縦長のため横幅が特に不足する。

| アップロード箇所 | 保存する長辺の上限 |
| --- | --- |
| Blog image_01〜04 | 400 → 1920px |
| Schedule top_image | 400 → 1920px |
| User pic_header / gallery_01〜04 | 400 → 1920px |
| Exhibition header_img / gallery_img_01〜04 | 400 → 1920px |
| ExhibitionGroupProfile header_img | 400 → 1920px |
| User pic_profile / Member・AdminUser image_profile / ExhibitionGroupProfile profile_img / EventAnswer icon | 400 → 640px |
| Column image | 1600 → 1920px |
| ChatMessage image | 既存2048pxを維持（暗号化・非公開） |

長辺1920pxはPCの960 CSS pxの表示で2倍密度を確保する目安。
縦長・横長とも縦横比を維持し、小画像を拡大保存しない。
向きを補正してから縮小し、JPEG品質88・プログレッシブ保存とする。
EXIFなどのメタデータは除去する。20MBの入力制限は維持し、
処理負荷のため60メガピクセル上限を追加した。

一覧の専用派生画像はヘッダー400×160 → 800×320px、
詳細ヘッダー960×384 → 1920×768px、品質78 → 82。
小さなプロフィール派生画像160×160pxは維持する。
URLの指紋に処理バージョンを含め、ディスク・ブラウザとも古い派生画像を再利用しない。
配信時の認可・ダウンロード元制限・容量制限・ロック・WebP・遅延読み込みは維持する。
新しい指紋の派生画像は初回アクセス時に生成され、初回変換のCPU・通信が増える。
旧キャッシュは削除せず残すため、必要に応じ別途使用量を確認する。

## 既存画像への効果と制限

共通アップローダーには原画像を別に保存するversionやバックアップ処理がなく、
保存先の通常ファイルが既に縮小されている。S3の世代管理や外部バックアップの有無は未確認。
既存画像の一括再処理・上書き・DB変更は行わない。
新しいアップロードに効果があり、既存画像は手元の元画像を再アップロードする必要がある。
一覧派生画像も、保存された元ファイル以上の細部は復元できない。

## 確認

`bundle exec ruby test/uploaders/image_uploader_url_check.rb`:
15テスト・118 assertions、失敗なし。全画像マウントの上限、縦長、小画像、JPEG品質、
向き補正の順序、画素数制限、旧拡張子・URL互換性を確認。

`bundle exec rails test test/integration/listing_images_test.rb`:
12テスト・63 assertions、失敗なし。専用ローカルPostgreSQLで画像配信、プリロード、キャッシュ、公開範囲、
フォールバック、ダウンロード制限、元ファイル保持を確認。

`bundle exec ruby ops/image_quality_preview.rb`:
外部通信・DBなしで実際のアップロード処理を比較し、
`output/image-quality/comparison.html`（画像埋め込みの単独HTML）とmetrics.jsonを生成する。
既存の1200×630pxのサイト画像を使用し、変更前400×210px・55,867 bytes、
変更後1200×630px・294,866 bytes。元画像は1,396,906 bytes。
このプレビューはアップロード処理の比較用であり、本番記事の書き換えではない。
ChromeのPC幅1440pxとiPhone 15相当（幅393px・DPR 3）で実画像を比較した。
両画面で画像の読み込み成功と横スクロールがないことを確認し、
`output/image-quality/desktop.png` と `mobile.png` に記録した。

本番デプロイやmasterへのpushは行わない（masterへのpushは本番自動デプロイを起動する）。
