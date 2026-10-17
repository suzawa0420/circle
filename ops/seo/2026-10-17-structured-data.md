# 公開ページの構造化データ整備（2026-10-17）

## 実装範囲

サークル・イベント・ブログ・対戦相手・コート体育館の一覧と詳細を確認し、画面に表示する公開情報からJSON-LDを生成するように整備した。既存のパンくず構造化も維持している。

| 対象 | 一覧 | 詳細 |
| --- | --- | --- |
| サークル | ItemListとCollectionPage | Organization、実際のAggregateRating・表示中のReview、回答済みFAQPage |
| イベント | ItemListとCollectionPage | 日時・公開会場がある場合はEvent。情報不足・オンラインの場合はWebPage |
| ブログ | ItemListとCollectionPage | BlogPosting、団体著者、公開日・更新日、本文、実際の投稿画像 |
| 対戦相手 | ItemListとCollectionPage | WebPageと募集団体への参照。日時未定の募集をSportsEventにはしない |
| コート・体育館 | ItemListとCollectionPage | LocalBusiness、SportsActivityLocationのadditionalType、住所・電話・公式URL・実際のAggregateRating |
| サークルのレビュー | 全体一覧はReviewを含むItemList | 団体のOrganizationにReview・AggregateRatingを関連付ける |
| 質問コーナー | 質問詳細へのItemList | WebPage内のQuestion、実際に回答済みの場合のみAnswer |

ジャンル・地域・固定条件・旧タグ系の一覧にも共通ヘルパーを適用した。ページングの正規URLと連続した項目位置を使用し、同じ一覧のJSON-LDが重複しないようにした。サークル一覧の旧 `/users` URLも実際の `/circles` URLに統一した。

## 出力条件とデータの整合性

- 公開GETページのみを対象とし、管理者表示・非公開団体・noindexページでは対象のJSON-LDを出力しない。
- JSONは共通パーシャルでエスケープし、投稿本文などによるscript要素の脱出を防ぐ。
- サークルは店舗と決め付けずOrganizationとし、複数ページから同じ団体IDを参照する。
- サークル詳細の個別レビューは画面と同じ最新3件。レビュー一覧では表示対象のレビューを使う。全体レビュー一覧から非公開団体を除外する。
- サークルの個別評価は保存されている0／1、集計評価は画面と同じ0〜5。欠損値・範囲外の値から架空の評価を作らない。
- 施設は公開レビューだけを集計し、画面にも対応する総合評価・件数を表示する。施設の匿名口コミには著者情報がないため、個別Reviewの著者を捏造せずAggregateRatingを使用する。
- 施設の汎用スポーツイラストを施設写真として扱わない。ブログとサークルは実際にアップロードされた画像だけを使用する。
- Eventは実際の日本時間の日時・公開会場を使用し、非公開住所・会員限定会場を含めない。深夜をまたぐ終了時刻にも対応する。
- EventのOfferは「無料」「500円」など単一価格を特定できる場合だけ出力する。複数料金や自由文から価格を推測しない。満員はSoldOut、中止・終了はOfferを省略する。
- 質問は実際に回答された内容のみAnswerにする。「未回答」などの仮回答は作らない。団体詳細で非表示となる質問はFAQにも含めない。
- 団体だけが回答できる質問コーナーは、利用者が別回答を投稿できるQAPageの要件を満たさないため、Question／AnswerをWebPageに関連付ける。

## Google上での扱い

構造化データは内容理解や対象の検索表示機能を支援するが、順位向上やリッチリザルトの表示を保証しない。ItemList、Organization、Questionなどは、付ければ必ず専用の検索表示が出るものではない。

GoogleのFAQリッチリザルトは2026年5月7日から表示終了とされている。回答済みFAQPageはschema.orgとしての意味付けを維持するもので、GoogleのFAQ枠を獲得する施策としては扱わない。

参考資料：

- [Google 構造化データの一般ガイドライン](https://developers.google.com/search/docs/appearance/structured-data/sd-policies)
- [Google Article](https://developers.google.com/search/docs/appearance/structured-data/article)
- [Google Event](https://developers.google.com/search/docs/appearance/structured-data/event)
- [Google Review snippet](https://developers.google.com/search/docs/appearance/structured-data/review-snippet)
- [Google QAPage](https://developers.google.com/search/docs/appearance/structured-data/qapage)
- [Google Searchの更新履歴（FAQ表示終了）](https://developers.google.com/search/updates)
- [schema.org SportsActivityLocation](https://schema.org/SportsActivityLocation)

## 検証と反映状況

関連するヘルパー・結合テストは **101件、1,877 assertions、失敗0・エラー0**。5種類の一覧・詳細、地域・ジャンル・固定条件、ページング、レビュー、回答有無、非公開・noindex、JSONエスケープ、イベントの料金・満員・不足情報を検証した。既存のパンくず、検索導線、イベント表示に関する回帰テストも含む。差分の空白検査も通過した。

秘密情報を読み込まない専用テスト起動ファイルとローカルの隔離PostgreSQLを使用した。本番データは変更していない。

ローカル実装まで完了。本番へのデプロイ、コミット、プッシュは未実施。新しいコードをGoogleのリッチリザルトテストやSearch ConsoleのURL検査で検証したとは扱わない。本番反映後に代表URLで再検証し、再クロール後の検索表示・対象クエリの順位・CTRを確認する。
