# キーワード検索の実行計画・CPU待ちの切り分け

## 確認済み

- 2026-09-25の提供されたServer3 vmstatでは、初回の起動以来平均を除きstが71〜73%、rが8〜10、idが0%。CPU実行待ちの影響が大きい。
- Server2は別の時刻にstが0〜1%。両方が常時同じ制限を受けるとは判断できない。
- 提供されたLightsailグラフでは両インスタンスのバースト残量がほぼ0%。
- 本番のSlow Requestのdb/viewは経過時間であり、DB自体のCPU使用時間ではない。CPU割当待ちや通信待ちを除外できない。dbとviewを加算しない。

## 追加修正

検索画面の空状態判定が@users.sizeで集計を行い、その後partialが別のrelationを作成して一覧取得、ページャーが再集計していた。
コントローラーでCircleListingDataを一度準備し、同じ上限付き関連取得のrelationを空状態判定・一覧・ページャーへ渡す。
空状態判定は表示対象ページをloadして判定するため、関連の全履歴は取得しない。変更は検索画面だけに適用し、他の一覧呼出しは既存の初期化経路を保つ。

隔離PostgreSQL16・合成データ・Rails6.0.5.1で画面処理を再現し、実際に発行されたSQLへEXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)を実行。
変更前はAggregate（ページ分の件数）、Limit（一覧）、Aggregate（全件数）の3回。変更後は一覧とページ数の2回。最終ページ・空ページは一覧の1回。
小規模合成データの時間を本番速度の根拠に使わない。

## 本番での読み取り専用確認（2026-09-25）

ChromeのLightsail SSHで両ホストに接続して確認した。データ行・認証情報・SQL全文は出力していない。

- Server3: 09:55:03 UTCからvmstat 1 10。初回を除く9サンプルはst=0%、id=78〜92%、r=0〜2、wa=0%。
- Server2: 09:56:11 UTCから同じ計測。初回を除く9サンプルはst=0〜2%、id=50〜94%、r=0〜3、wa=0%。
- 同時刻ではなく約1分差の短い標本。以前のServer3の高いstealは今回再現しなかったが、解消・原因除去を意味しない。
- 両ホストから実際の検索コントローラーのprivateなrelation構築処理のみを呼び出し、「東京」/sort=1/page=1について一覧・総件数のEXPLAIN (FORMAT JSON)を取得。検索アクション自体は呼ばず、検索履歴の書込みを避けた。
- READ ONLYトランザクション、statement_timeout=5000ms、lock_timeout=1000ms、プロセス上限60秒。ANALYZEは付けず、終了時rollback。両方とも取得成功。
- 両ホストで同じ計画。一覧: Limit(20) → Gather Merge → Sort → usersの並列Seq Scan。LimitのTotal Cost=11237.53、ScanのPlan Rows=26157、Total Cost=9539.15。
- 総件数: Aggregate → Gather → Aggregate → usersの並列Seq Scan。最上位Total Cost=10604.77。
- users_cities/user_tagsはBitmap Index Scanを利用。関連表すべてが無索引という状態ではない。
- 推定行数は総登録数ではなく、costもミリ秒ではない。実行時間・バッファ・DB側CPU・実際のループ回数は今回未計測。

したがって、重複COUNTを除く修正は同じ検索条件の再評価を減らすが、残る一覧と総件数の走査自体は解消しない。追加インデックスや検索仕様変更は別途、実測と検索一致性の検証が必要。

## 本番で次に必要な読み取り専用確認

1. 両ホストで同じ時刻にvmstat 1 10を取得し、初回を除外してst/us/sy/id/rを比較する。
2. 実際の「東京」検索・先頭ページ・通常並び順の一覧SQLと総件数SQLについて、まずEXPLAIN (FORMAT JSON)だけを取得する。ANALYZEは実クエリを実行するため初回には付けない。
3. 許可する出力はノード種別・対象テーブル/インデックス名・推定行数・コスト・ループ等の数値に限定し、SQL全文、Filter条件、利用者入力、データ行、接続情報は出さない。
4. statement_timeoutとlock_timeout、読み取り専用トランザクションを設定する。必要なら承認を得て閑散時に単発のEXPLAIN ANALYZEを行う。
5. 広範な部分一致のSeq Scan、ソート、繰り返しSubPlan、COUNTの費用を確認してからインデックスや検索構造変更を判断する。

今回の計測・master反映・デプロイはユーザー承認済み。本番DDL、CPUプラン変更、ワーカー数変更は行わない。
反映はServer3→Server2の既存Actions、追加migrationなし、アセット生成とUnicorn順次再起動あり。
ロールバックは今回追加するコミットのみrevertして再展開する。
