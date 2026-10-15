# 種目追加と検索改善（2026-10-15）

## 実装

- ソフトテニス（59 / soft-tennis）、ピックルボール（60 / pickleball）、スキー（61 / ski）。既存の種目登録・検索・OGP画像の仕組みを利用する。
- 主種目に加えて補助種目を3つまで登録可能。全国・地域・詳細検索・タグ・イベント検索・サイトマップに反映。団体詳細URLは維持する。
- 主催者が入力する活動スタイル、参加レベル、体験参加、道具、集合場所、活動先、日帰り／宿泊。空欄は推測せず非表示。入力は200文字まで。
- 種目別の短い案内、募集がある関連種目・地域へのリンク。既存の0件noindexとcanonical方針を維持する。
- 別名の軟式テニス、サイクリング、ポタリング、ハイキング、低山登山、ウォーキング、ジョギング、マラソンを既存種目に対応。活動スタイルの厳密な絞り込みとは異なる。

## 分類

20261015020000 のマイグレーションは公開ページを確認した以下の団体だけを対象にする。ID・旧種目・名称の条件が一致しなければ変更しない。公開状態・警告・募集状態・ランキング・更新日時は変えない。

| 団体ID | 根拠URL | 変更 |
|---|---|---|
|21302|https://circle-book.com/circles/21302|テニス→ソフトテニス|
|26929|https://circle-book.com/circles/26929|テニス→ソフトテニス|
|14807|https://circle-book.com/circles/14807|テニス→ピックルボール|
|13737|https://circle-book.com/circles/13737|テニス→ピックルボール|
|10942|https://circle-book.com/circles/10942|スノーボード→スキー。古い募集・既存警告も維持|
|11833|https://circle-book.com/circles/11833|スノーボードを維持し補助種目スキーを追加|

残りは運営の「サークル・主催者管理→種目の分類確認」または読み取り専用 `bundle exec rails sports:audit` で候補を確認する。キーワード一致だけで一括変更しない。サーフィンは候補確認対象に含め、募集の実態が確認できるまで新種目として公開しない。

## 計測

- dataLayer の `sport_listing_click` と `sport_inquiry_delivered` に `sport`（主種目slug）を付与。氏名・本文・メール・団体IDを送らない。
- 配信済み問い合わせの送信時だけ完了マーカーを出す。審査保留・失敗は完了に数えない。継続問い合わせも含むためユニーク新規問い合わせ数ではない。
- GTM/GA4側のイベント転送・カスタムディメンション設定はアプリ変更だけでは完了しない。プレビューで受信確認後、既存計測設定に追加する必要がある。
- 現在の問い合わせフォームはサイト内メッセージを使用する。外部応募ボタンの追加はしない。
- `sports:metrics` は種目別の募集中団体数・90日以内の更新数・直近28日間の配信済み参加者メッセージがある会話数をJSON行形式で出力する。補助種目は重複計上されるため種目間合計はサイト全体件数にならない。
- Search Console連携は現在取得エラー。表示回数・クリック・順位の確認は復旧後に行う。

## デプロイ

対象候補：circle-book.com / master / AL2023 server4・server5。master pushでGitHub Actionsがテスト、アセット生成、明示した3マイグレーション、順次Pumaホットリスタート、公開ページ検証、サイトマップ公開を実行。

追加列2つとGINインデックス、種目3件、確認済み分類変更を含む。GINはconcurrently。列追加には短いテーブルロックが必要。計画停止は設けないが、再起動・ロック待ちで一時的な応答遅延の可能性がある。

ロールバックは修正を打ち消すコミットを通常フローで配信。追加列・種目・画像は残す。分類変更を機械的に逆戻しして後の主催者編集を上書きしない。

## 画像

ユーザー承認により、指定CLIのモデル非対応エラー後、このチャットの組み込みimage_genに切り替えた。APIキー・直接API呼び出しは使用していない。実在団体の写真ではなく、写真風の生成イメージ。

成果物：public/images/events/soft-tennis.jpg、pickleball.jpg、ski.jpg。既存画像と同じ500×333、RGB、プログレッシブJPEG。元画像を1536×1024で生成し、縮小して保存。

生成プロンプトの共通条件：photorealistic editorial sports equipment photograph, landscape 3:2, natural daylight, authentic material textures, central overhead-oblique framing for 500x333 thumbnail, no people/text/branding/watermark。

- soft-tennis: two slim strung soft tennis rackets and three smooth white rubber balls on a green outdoor court; no fuzzy yellow tennis balls。
- pickleball: two solid flat carbon-fiber paddles with short handles and three perforated yellow balls on a blue court; no strings。
- ski: exactly two alpine skis with realistic bindings and two poles on textured snow; not a snowboard。

## 検証結果

2026-10-15：本番認証情報を参照しない専用PostgreSQLで117テスト・1,698アサーション成功。種目・補助種目・地域・カテゴリ・詳細検索・イベント検索・サイトマップ・編集権限・分類移行の条件・問い合わせ・管理画面・既存SEOを検証。JavaScript計測テスト2本、Zeitwerk、アセット生成、公開一覧の計測コード組み込み、ブランドアセット検証も成功。画像3枚はJPEG/RGB/500×333を確認済み。
