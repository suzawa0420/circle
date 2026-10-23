# 画像生成記録

- 実施日: 2026-10-23
- 使用: Codex組み込みimage_gen。画像ごとに個別呼び出し。APIキー・Images API・scripts/image_gen.pyは不使用。
- codex execは起動エラーのため生成には使用できず、このセッションの組み込みimage_genを直接使用。
- 保存先: content/columns/2026-10-more-genres/images/
- 全14枚: PNG、1536×1024。生成出力をそのままコピー。リサイズなし。寸法・内容を確認。
- 記事・コード・既存baseball-first.pngは変更なし。

## 共通プロンプト

各呼び出しは、以下に ` Scene: ` と個別プロンプトを連結して実行。transparent_background=false。

1536x1024 horizontal PNG. Natural bright photorealistic lifestyle photograph for a Japanese editorial article. Main equipment grouped centrally, authentic textures and soft daylight, no people, no text, no numbers, no logos, no watermark. Generic unbranded tools, not a replica of a commercial product image. A single coherent photographed scene.

## 個別プロンプトと保存結果

### dance-first.png

木床のダンススタジオ、バッグ、室内スニーカー、無地の練習着、タオル、水筒。

保存成功: `dance-first.png` — PNG、1536×1024。

### swimming-first.png

明るい屋内プールの水面を背景に、ベンチ上の水着、ゴーグル、キャップ、タオル、防水ポーチ。

保存成功: `swimming-first.png` — PNG、1536×1024。

### molkky-organizer.png

公園の平らな土の地面、木製の投げ棒とモルックのピン12本、運搬バッグ、スコア用紙。ピンと用紙は無地、読める文字数字なし。

再生成時の追加指示: 木製ピンを正確に12本、4本ずつの3列に間隔を空けて配置し、やや俯瞰で全12本を別々に数えられるよう撮る。投げ棒はその12本とは別に1本を横に置く。

保存成功: `molkky-organizer.png` — PNG、1536×1024。初回画像を確認後に再生成し、最終画像で差し替え。

### walking-first.png

日本の街歩きの公園ベンチ、歩きやすい靴、軽いバッグ、帽子、折りたたみ傘、小さなボトル。

保存成功: `walking-first.png` — PNG、1536×1024。

### cooking-first.png

清潔な共同調理室の調理台、エプロン、三角巾、ふきん、密閉容器、保冷バッグ。

保存成功: `cooking-first.png` — PNG、1536×1024。

### bouldering-first.png

屋内ボルダリング壁の手前、レンタルシューズ、チョークバッグ、ブラシ、練習着、タオル。

保存成功: `bouldering-first.png` — PNG、1536×1024。

### cycling-first.png

川沿いのサイクリングロードに停めたロードバイク、その前に自転車用ヘルメット、ライト、携帯ポンプ、小型工具、グローブ。

保存成功: `cycling-first.png` — PNG、1536×1024。

### snow-first.png

スキー場ロッジの木製ベンチ、雪山を背景にゴーグル、グローブ、長い靴下、ベースレイヤー、ネックウォーマー。

再生成時の追加指示: ベースレイヤーは襟元を内側に折り込んだ完全な無地。内側も外側もプリント、タグ、ラベル、縫い付け文字が一切見えない。

保存成功: `snow-first.png` — PNG、1536×1024。初回画像を確認後に再生成し、最終画像で差し替え。

### camping-first.png

緑のキャンプ場、テント手前のテーブルにヘッドライト、カップ、皿、寝袋、折りたたみチェア。火や調理器具なし。

保存成功: `camping-first.png` — PNG、1536×1024。

### badminton-organizer.png

明るい体育館、バドミントンコートの脇にシャトルの筒、回収筒、得点板、タイマー、収納箱、貸出ラケット。得点板とタイマーは無表示、文字数字なし。

保存成功: `badminton-organizer.png` — PNG、1536×1024。

### volleyball-organizer.png

体育館のバレーコートの脇、青黄のボール、空気入れ、圧力計、運搬バッグ、得点板、ホイッスル。文字数字なし。

保存成功: `volleyball-organizer.png` — PNG、1536×1024。

### futsal-organizer.png

屋内フットサルコートの脇、フットサルボール、色違いビブス、低いマーカー、空気入れ、タイマー、笛。文字数字なし。

保存成功: `futsal-organizer.png` — PNG、1536×1024。

### table-tennis-organizer.png

卓球台の脇、オレンジと白の練習ボール、球拾いネット、かご、得点板、予備ラケット。文字数字なし。

保存成功: `table-tennis-organizer.png` — PNG、1536×1024。

### reception-organizer.png

明るい貸し会議室の受付机、無記名の名札、卓上案内板、クリップボード、釣銭トレー、タイマー。個人情報・文字数字なし。

保存成功: `reception-organizer.png` — PNG、1536×1024。
