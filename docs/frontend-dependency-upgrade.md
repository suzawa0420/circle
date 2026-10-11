# Frontend dependency update (2026-10-11)

## 更新内容

- jQuery: 実際に読み込むエントリーを1.12.4から3.7.1へ変更（jquery-rails 4.6.1付属）。Bootstrap 3との互換性を保つため4系は採用しない。
- jQuery UI: 1.12.1から1.14.2へ更新。使用しているDatepickerとその依存部品（version/keycode）、日本語ロケール、テーマのみをローカル配信。RawGitとjQuery UI CDNへの依存を廃止。
- Bootstrap Sass: 3.3.7から3.4.1へ更新。既存のクラス・画面レイアウトを維持。
- Sassビルド: sassc-railsからdartsass-sprockets 3.2.1へ変更。sassc-embedded 1.80.10経由でDart Sass 1.105.1を使用。Bootstrapのgem依存によりsassc 2.4.0自体はロックファイルに残る。
- lib/assetsの変更も本番アセット再生成の判定対象に追加。一般公開の一覧は引き続き軽量バンドルのみを読み込む。

## 残る移行

Bootstrap 3はEOLであり、3.4.1への更新だけで継続保守が得られるわけではない。Bootstrap 5への移行はクラス・レイアウト・JavaScript部品を含む別工程とする。Bootstrap由来のSassの旧記法およびアプリの@importに非推奨警告が残る。Turbolinks→Turboもフォーム送信、チャット、画面キャッシュへの影響を分けて検証するため今回には含めない。

## jQuery UIの取得元

すべてタグ1.14.2の公式ソース。著作権表示を維持し、ライセンスはlib/assets/JQUERY-UI-LICENSE.txtに同梱。

- https://raw.githubusercontent.com/jquery/jquery-ui/1.14.2/ui/version.js
- https://raw.githubusercontent.com/jquery/jquery-ui/1.14.2/ui/keycode.js
- https://raw.githubusercontent.com/jquery/jquery-ui/1.14.2/ui/widgets/datepicker.js
- https://raw.githubusercontent.com/jquery/jquery-ui/1.14.2/ui/i18n/datepicker-ja.js
- https://raw.githubusercontent.com/jquery/jquery-ui/1.14.2/themes/base/core.css
- https://raw.githubusercontent.com/jquery/jquery-ui/1.14.2/themes/base/datepicker.css
- https://raw.githubusercontent.com/jquery/jquery-ui/1.14.2/themes/base/theme.css
- https://raw.githubusercontent.com/jquery/jquery-ui/1.14.2/themes/base/images/ （同梱PNG各種）

JSはversion/keycode/datepickerの順で連結。CSSはcore/datepicker/themeを連結し、画像urlをSprocketsのasset-urlに変更。日本語ロケールと画像は未加工。

### 配置後SHA-256

- `85c0f7b80c3447a191a6413f7d4439a818910b11e8ec763086f2cbf4a4495572` `lib/assets/javascripts/jquery-ui-datepicker.js`
- `0e425b37fca62f97468333b3e24dd2ff0b137f63aa39a50a40633d6bf7edfdcf` `lib/assets/javascripts/datepicker-ja.js`
- `dbec473b19302918dcd33be49dac4113f78f0b115d6c6b6fa04cc7002e25c66e` `lib/assets/stylesheets/jquery-ui.scss`
- `42f3fd7ecbd1e18e5e9c5cbbc2ba9ce4d81a388258a81833d38819a1406ff48d` `lib/assets/images/jquery-ui/ui-icons_444444_256x240.png`
- `9dab1725ee38e87989a48796505748157d0238ac72c25a072f5162aa61e2da06` `lib/assets/images/jquery-ui/ui-icons_555555_256x240.png`
- `91e1ea5f253e72e2e9402cff2bb58fa98b5faa49f9ded999c760013b94ead7f8` `lib/assets/images/jquery-ui/ui-icons_777620_256x240.png`
- `943d9bc18134619d37406debd81636b63881363a019513c1d6e6cb13b5c5fb30` `lib/assets/images/jquery-ui/ui-icons_777777_256x240.png`
- `6efc1db612130b63222e0f6bf54d37392c3f2bdb2c10ba50f5d0f1e14d63af61` `lib/assets/images/jquery-ui/ui-icons_cc0000_256x240.png`
- `6d81fc3fac3b17a25f4ef3eee1394642d38b1adba5c7442acef3b3c8b045cbe7` `lib/assets/images/jquery-ui/ui-icons_ffffff_256x240.png`

## 検証

- ローカルの隔離DBで画面、日程コピー、参加者アカウント、チャット、一覧CSSの回帰テスト79件/1,129項目成功。追加後のruntimeテスト20件/229項目成功。
- Dart Sassによる全アセット生成、ブランド色検証、本番相当の起動とスタブSES配信に成功。
- Playwrightで架空アカウントのログイン、日本語カレンダー、過去日禁止、選択日2026-10-12での日程保存、モバイルメニューを確認。外部通信は遮断し、広告等の通信失敗は対象外。
- 実ブラウザーでjQuery 3.7.1 / Datepicker 1.14.2 / Bootstrap 3.4.1を確認。

## 本番反映

masterへのプッシュで既存deploy_prodワークフローを実行。Linux上の全チェック成功後、server4/server5の順でアセット準備・Pumaの段階的切替を行う。新規マイグレーションは追加しない。旧アセット・gemを保持し、必要ならこの変更のrevertコミットを同手順で反映する。
