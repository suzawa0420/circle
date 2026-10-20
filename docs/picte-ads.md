# PICTE広告

写真・カメラ（`Event.ruby == 'camera'`）に絞ったサークル検索結果と、同種目のサークルの主催者マイページに表示。
一般のサークル一覧や他種目の検索には表示しない。検索結果は4件目の後（4件未満なら末尾）、0件なら検索結果の案内の下に1枠。
マイページは「活動を管理」の直後。過去の地域限定・期限付きPICTE広告は置き換え。

画像はユーザー指定の `https://picte-photo.com/wp-content/uploads/0921_0148.jpg` をそのまま
`public/images/ads/picte-share-exhibition.jpg` に保存。1280 × 853、約102KB。画像生成・編集なし。
遷移先は `https://picte-photo.com/service/share-exhibition/`。

## クリック数

運営メニューの「PICTE広告クリック数」（`/super_admin/picte_ad_clicks`）で累計と直近30日の日別件数を確認。
専用のウェブマスターログインが必要。PICTE側の設定やGTMの公開作業に依存しない。

リンクのクリック時に同一オリジンの `POST /picte-ad-clicks` へCSRFトークンと配置だけを送信。
`sendBeacon` が受理しなかった場合に限り `fetch(keepalive)` にフォールバックする。
本文・画像・ボタンは同じリンク。通常、修飾キー、キーボード、中ボタンの操作を対象とし、右クリックやキャンセル済みイベントは数えない。
JavaScript無効・ネットワーク障害・ブラウザー側の制限などで未記録になる場合はある。

保存するのは日本時間の日付、`search` / `mypage`、クリック数だけ。訪問者IDやサークルIDは保存しない。
表示数、クリック率、ユニーク人数は計測しない。同じ人の再クリックも加算。
日付・配置の一意インデックスとDBの原子的な加算で、両サーバーからの同時クリックを集計する。
CSRF検証とIP単位60回/5分の既存スロットル基盤で保護する。

## GA4向けUTM

共通：`utm_source=circlebook`、`utm_medium=display`、`utm_campaign=picte_share_exhibition`。
検索：`utm_content=camera_search_v1`、主催者：`utm_content=organizer_mypage_v1`。
PICTEのGA4でセッション参照元/メディアとセッションの手動広告コンテンツを確認できる（PICTE側のGA4設定・同意状態に依存）。
訪問セッション数とサークルブックのクリック数は一致しない。

追加で `dataLayer` に `picte_ad_click` と `placement` を送る。
このイベントをサークルブックのGA4にも送る場合は、GTM側のイベントタグの設定が別途必要。
運営画面の件数はGTM未設定でも確認できる。

## デプロイ

masterの通常フローでserver4・server5に反映。追加マイグレーション `20261020000000` は日別集計の新規テーブルのみ。
既存データ変更なし。アセット生成後、Pumaを順次ホットリスタート。
ロールバックはrevertコミットを通常配信。集計テーブルは残し、既存の本番データを戻す操作はしない。
