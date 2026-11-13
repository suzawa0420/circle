# 全国公式サイト探索入口の根拠

確認日: 2026-11-13。`config/place_import_official_directories.json` は47都道府県の公式サイトorigin一覧。施設一覧や施設詳細の検証済みソース一覧ではない。

## 根拠・確認方法

- 独立行政法人福祉医療機構 WAM NET「都道府県庁ホームページ」: https://www.wam.go.jp/content/wamnet/pcpub/top/link/top_link04.html
- 上記の全47リンクをWeb閲覧で照合。旧URLの福島、石川、福井、大阪、兵庫、奈良、岡山は各県公式サイトの現在のドメインへ補正。
- 栃木の直接閲覧はtimeoutだったが、公式サイトの検索結果でドメイン実在を確認。通信成功を保証しない。
- 全国の市町村への追加入口: J-LIS「全国自治体マップ検索」 https://www.j-lis.go.jp/spd/map-search/cms_1069.html 。都道府県から市町村公式サイトを探せるが、スポーツ施設の網羅性を保証するものではない。

## 補正ドメインの一次資料

- 福島 https://www.pref.fukushima.lg.jp/
- 石川 https://www.pref.ishikawa.lg.jp/index.html
- 福井 https://www.pref.fukui.lg.jp/doc/dx-suishin/homepage/ssl.html
- 大阪 https://www.pref.osaka.lg.jp/o070050/koho/information/use.html
- 兵庫 https://web.pref.hyogo.lg.jp/howto/index.html
- 奈良 https://www.pref.nara.lg.jp/index.html
- 岡山 https://www.pref.okayama.lg.jp/

## スポーツ施設向けの個別入口候補

以下は別途アダプタ・規約・robots・根拠を確認する候補であり、この一覧への記載だけで自動公開を許可しない。

- 鳥取市 https://www.city.tottori.lg.jp/page/6155.html : 体育館・テニス等の区分別に住所、利用時間、料金、電話、休館条件を掲載。ページ更新2025-10-20。駐車場・種目・規模は別途確認が必要。
- 島根県 https://www.pref.shimane.lg.jp/sport/shogai/shisetsu/ : 県立6施設と公共施設ガイドに公式リンク。外部運営元へのリンクは自動で取得許可しない。
- 福井県 https://f-sports.pref.fukui.lg.jp/facility : 県内施設を種目別検索できる県公式ポータル。
- 福井県 https://www.pref.fukui.lg.jp/doc/dx-suishin/opendata/list_ct.html : 県・17市町の公共施設CSV。所在地、電話、開館時間、休館日等。ライセンスと更新日確認が必要。
- 福井市 https://www.city.fukui.lg.jp/kyoiku/sports/sisetu/index1.html : スポーツ施設一覧。
- 福井市 https://www.city.fukui.lg.jp/kyoiku/sports/sisetu/index.html : スポーツ施設カテゴリ。

## 制約

- 各サイトの利用規約・robots・XML sitemapは本調査では未検証。公式サイトであることは、公開取得・転載・自動公開の許可と同義ではない。
- 実行時にrobots、URLスコープ、通信制限、サイズ制限等を確認し、不明・拒否・障害なら停止または保留する。Mizuno等の拒否を回避するための入口ではない。
- originは同一サイト探索の出発点に限る。発見された外部ドメインやサブドメインへ許可を拡張しない。
- 都道府県公式サイトだけでは市町村・指定管理者の全施設を網羅しない。47都道府県の入口があることと、47都道府県の施設登録完了を区別する。
- 候補URLの発見と施設情報の検証・登録を分離し、未知形式、料金・住所・種目・営業時間・駐車場等の根拠不足、閉鎖・工事・制限、重複疑義を保留する。
