# frozen_string_literal: true

# Keep answers and search keywords together so the public help and contact form agree.
class HelpCatalog
  AUDIENCES = { 'all' => 'すべて', 'member' => '参加者向け', 'owner' => '主催者向け' }.freeze
  CATEGORIES = { 'account' => 'ログイン・アカウント', 'message' => 'メッセージ・参加', 'listing' => '募集・サークル管理', 'review' => '口コミ・通報', 'other' => 'その他' }.freeze
  ARTICLES = [
    { id: 'about', audience: 'all', category: 'other', title: 'サークルブックとは？料金はかかりますか？', keywords: '無料 有料 お金 利用料', content: [
      { paragraph: "サークルやチームがメンバーを募集し、参加希望者が活動を探せるサービスです。サークルブックの登録・募集・メッセージ機能は無料です。" },
      { paragraph: "活動の参加費や会費はサークルごとに異なるため、主催者に確認してください。" }
    ], action: :circles },
    { id: 'login', audience: 'all', category: 'account', title: 'ログインできない・パスワードを忘れた', keywords: 'ログオン 入れない ログインできません ログイン出来ない パスワード忘れた パスワード リセット 再設定', content: [
      { heading: "ログイン画面を確認する" },
      { paragraph: "参加者と主催者はログイン画面が異なります。登録した種類の画面を開き、登録メールアドレスを確認してください。" },
      { heading: "パスワードを忘れた場合" },
      { paragraph: "パスワードを忘れた場合は、その画面の「パスワードを忘れた方」から再設定できます。" },
      { heading: "ログインが制限された場合" },
      { paragraph: "繰り返し失敗して制限された場合は、時間を置いてお試しください。" }
    ], action: :login },
    { id: 'reset-mail', audience: 'all', category: 'account', title: 'パスワード再設定・メール確認のメールが届かない', keywords: '認証 確認メール 迷惑メール メールアドレス', content: [
      { heading: "受信設定・登録情報を確認する" },
      { paragraph: "迷惑メールフォルダ、受信拒否設定、入力したメールアドレスを確認してください。参加者と主催者のどちらで登録したかも確認してください。" },
      { heading: "確認メールを再送する" },
      { paragraph: "確認メールは、ログイン後のメール確認画面から再送できます。何度も送信せず、少し待ってから確認してください。" }
    ], action: :login },
    { id: 'account-edit', audience: 'all', category: 'account', title: 'メールアドレス・パスワードを変更したい', keywords: '登録情報 設定 変更', content: [
      { paragraph: "登録した種類のアカウントでログインし、アカウント設定から変更してください。" },
      { paragraph: "メールアドレスを変更した場合は、新しいアドレスの確認が必要です。" }
    ], action: :account },
    { id: 'contact-circle', audience: 'member', category: 'message', title: 'サークルに参加・見学したい。どこから連絡する？', keywords: '応募 問い合わせ 申込 申し込み 入会', content: [
      { heading: "主催者に連絡する" },
      { paragraph: "サークルのページで募集内容と参加条件を読み、メッセージのボタンから主催者に連絡してください。参加者登録とメールアドレスの確認が必要です。" },
      { heading: "参加前に確認すること" },
      { paragraph: "見学日・参加費・持ち物などは主催者に確認してください。運営は参加の受付や日程の調整を代行していません。" }
    ], action: :circles },
    { id: 'no-reply', audience: 'member', category: 'message', title: '主催者から返信が来ない', keywords: '返事 未返信 無視 連絡 来ない', content: [
      { heading: "メッセージと受付状況を確認する" },
      { paragraph: "送信したメッセージと受付状況をメッセージ一覧から確認してください。主催者の活動状況により返信に時間がかかる場合があります。待っても返信がない場合は、別のサークルへの参加もご検討ください。" },
      { heading: "初回返信がないことを報告する" },
      { paragraph: "お問い合わせが届いてから3日以上、初回返信がない場合は会話画面から報告できます。報告人数はサークルのプロフィール等に表示され、主催者が返信すると件数から外れます。" },
      { heading: "返信・参加の保証について" },
      { paragraph: "運営から返信や参加を保証することはできません。" }
    ], action: :messages },
    { id: 'message-notification', audience: 'all', category: 'message', title: 'メッセージ・通知を確認したい', keywords: "メール 通知 チャット 履歴 受信 旧お問い合わせ 返信アドレス 返信欄 2026年10月", content: [
      { heading: "2026年10月からの変更" },
      { paragraph: "2026年10月から、新しいお問い合わせと返信はサークルブックのサイト内メッセージでやり取りする方法に変わりました。以前の旧お問い合わせは、問い合わせ者のメールアドレスへ直接返信する方法でした。現在の通知メールに直接返信しても、相手への返信にはなりません。" },
      { heading: "通知後にログインする" },
      { paragraph: "未読のメッセージは登録メールアドレスへ通知メールでお知らせします。通知が届いたら、主催者は「主催者ログイン」、参加者は「参加者ログイン」から、やり取りに使っているアカウントでログインしてください。別の種類のアカウントや別のメールアドレスでログインしていると、該当する会話は表示されません。" },
      { heading: "メッセージを確認・返信する" },
      { steps: ["ログイン後に「メッセージ」を開き、該当する会話を選んでください。", "画面下の「メッセージを入力」欄に返信を書き、「送信」を押してください。"] },
      { paragraph: "通知メール内のリンクからも会話を開けます。" },
      { heading: "未読・既読の表示" },
      { paragraph: "会話を開くと届いたメッセージが既読になり、一覧の未読数が消えます。自分が送ったメッセージには、相手が会話を開くと「既読」と表示されます。画面を開いたままの場合、表示の更新には最大15秒ほどかかります。" },
      { heading: "写真を送る・見る" },
      { paragraph: "入力欄の左のカメラボタンから、1メッセージにつき写真1枚（10MBまで）を選び、送信できます。届いた写真はタップで拡大でき、長押しで保存できます。" },
      { heading: "通知メールが届かない場合" },
      { paragraph: "通知メールが届かなくても、サイト内のメッセージを直接確認してください。迷惑メールフォルダと登録メールアドレスもご確認ください。" }
    ], action: :messages },
    { id: 'owner-reply', audience: 'owner', category: 'message', title: '参加希望者への返信方法・返信が来ない場合', keywords: "参加者 応募 チャット 返事 旧お問い合わせ 返信方法 返信欄 名前 メールアドレス 通知 新システム", content: [
      { heading: "旧お問い合わせとの違い" },
      { paragraph: "以前の旧お問い合わせは、問い合わせ者の名前やメールアドレスからメールを作成し、相手のメールアドレスへ直接返信する方法でした。2026年10月から、新しいお問い合わせはサイト内メッセージでやり取りする方法に変わりました。新しいお問い合わせの通知メールへ直接返信することはできません。" },
      { heading: "現在のお問い合わせへの返信手順" },
      { paragraph: "通知メールが届いたら、次の手順で返信してください。" },
      { steps: ["サークルを管理している「主催者」アカウントでログインします。", "「メッセージ」を開き、該当する参加者との会話を選びます。", "画面下の「メッセージを入力」欄に返信を書いて「送信」を押します。"] },
      { paragraph: "返信先のメールアドレスを入力する必要はありません。通知メール内のリンクからも会話を開けます。" },
      { heading: "会話が見つからない場合" },
      { paragraph: "会話が見つからない場合は、参加者アカウントや別の主催者アカウントでログインしていないか確認してください。参加者として主催者からの返信を確認する場合は、問い合わせに使った「参加者」アカウントでログインし、「メッセージ」から確認・返信してください。" },
      { heading: "過去の旧お問い合わせに返信する" },
      { paragraph: "過去の旧お問い合わせは、主催者マイページの「お問い合わせ管理」で確認し、従来どおり相手のメールアドレスへ直接返信してください。旧お問い合わせはサークルレベルの未返信減点の対象外です。" },
      { heading: "参加希望者から返信がない場合" },
      { paragraph: "参加希望者から返信がない場合、運営は代理連絡や参加の確約を行えません。" }
    ], action: :messages },
    { id: 'inquiry-guidance', audience: 'owner', category: 'message', title: '問い合わせ前の確認事項・自動案内を設定したい', keywords: 'テンプレート 自動返信 注意事項', content: [
      { paragraph: "対象サークルの管理画面から「お問い合わせ内容の編集」を開いて設定します。参加条件や参加希望者に伝えたい内容を記入してください。" },
      { paragraph: "変更後の案内は、それ以降に始まる新しい問い合わせに反映されます。" }
    ], action: :owner_dashboard },
    { id: 'edit-listing', audience: 'owner', category: 'listing', title: '募集内容・活動日・画像を編集したい', keywords: '変更 更新 ブログ スケジュール 写真 募集停止', content: [
      { paragraph: "主催者管理画面で対象サークルを選び、基本情報、ブログ、スケジュールなどを編集してください。" },
      { paragraph: "募集を止める場合は基本情報の募集状態を変更します。保存後、サークルの公開ページも確認してください。" }
    ], action: :owner_dashboard },
    { id: 'ranking', audience: 'owner', category: 'listing', title: 'サークルの表示順・レベルについて知りたい', keywords: '順位 上位 検索 ランキング ポイント', content: [
      { paragraph: "表示順は一覧の並び替え条件によって変わります。サークルレベルの内訳は主催者管理画面で確認できます。" },
      { paragraph: "活動スケジュール・ブログ・質問への回答などを、実際の活動に合わせて更新してください。更新だけで特定の順位を保証するものではありません。" }
    ], action: :owner_dashboard },
    { id: 'listing-hidden', audience: 'owner', category: 'listing', title: 'サークルが検索に出ない・公開されない', keywords: '非公開 停止 審査 表示 見つからない', content: [
      { heading: "管理画面・検索条件を確認する" },
      { paragraph: "管理画面で募集状態、登録内容、公開停止や確認待ちの案内を確認してください。検索条件の地域・種目も確認してください。" },
      { heading: "運営に確認を依頼する場合" },
      { paragraph: "公開停止に関する個別の確認が必要な場合は、サークル名と公開ページのURLを添えて運営にお問い合わせください。" }
    ], action: :owner_dashboard },
    { id: 'solicitation-warning', audience: 'owner', category: 'listing', title: 'ネットワークビジネス・宗教勧誘の注意喚起を消したい', keywords: 'マルチ商法 アムウェイ ニュースキン 宗教 勧誘 警告 注意 表示 取り消し 取消 解除 削除 消してほしい 誤判定', content: [
      { heading: "注意喚起を表示する理由" },
      { paragraph: "この注意喚起は、アムウェイ・ニュースキンなどのネットワークビジネス（マルチ商法）への勧誘や、宗教への勧誘を目的としている可能性があると、当サイト独自の判定基準で判断した場合に表示しています。勧誘目的であると断定するものではなく、参加を検討する方への注意喚起です。" },
      { heading: "表示の解除について" },
      { paragraph: "参加者の安全のため、注意喚起の表示は原則として解除しません。主催者ご自身で表示を消すこともできません。" },
      { paragraph: "「勧誘していない」「表示を消してほしい」という申告だけを理由とした解除依頼には応じられません。" },
      { heading: "具体的な事実誤認がある場合" },
      { paragraph: "別のサークルとの取り違えなど、判定の前提に具体的な事実誤認がある場合は、サークル名・公開ページのURL・誤っている事実・確認できる資料を添えて、運営へお知らせください。事実確認のために受け付けるもので、表示の解除を保証するものではありません。" },
      { paragraph: "パスワードや、確認に不要な参加者の個人情報は送らないでください。" }
    ], action: :contact },
    { id: 'delete-circle', audience: 'owner', category: 'listing', title: 'サークルを削除したい', keywords: '消す 削除 募集終了', content: [
      { paragraph: "主催者管理画面で対象サークルを選び、「サークルを削除する」から手続きしてください。" },
      { paragraph: "関連するデータも削除されます。操作画面に表示される対象と注意事項を確認してから実行してください。" }
    ], action: :owner_dashboard },
    { id: 'withdraw-member', audience: 'member', category: 'account', title: '参加者アカウントを退会したい', keywords: '退会 解約 削除 アカウント 消す', content: [
      { paragraph: "参加者アカウントでログインし、退会手続き画面から操作してください。削除対象や注意事項は手続き画面で確認できます。" },
      { paragraph: "退会を実行する前に必要な情報を確認してください。" }
    ], action: :withdraw_member },
    { id: 'withdraw-owner', audience: 'owner', category: 'account', title: '主催者アカウントを退会したい', keywords: '退会 解約 削除 アカウント 消す', content: [
      { paragraph: "主催者アカウントでログインし、退会手続き画面の削除対象と注意事項を確認してください。" },
      { paragraph: "サークルだけを削除する場合は、サークル管理画面から操作してください。" }
    ], action: :withdraw_owner },
    { id: 'reviews', audience: 'owner', category: 'review', title: 'サークルに投稿された口コミを削除したい', keywords: '評価 レビュー 削除 消す 匿名 旧口コミ 参加者', content: [
      { paragraph: "サークルの口コミには、メッセージでやり取りした参加者が投稿する「現在の口コミ」と、以前に匿名で投稿できた「旧口コミ」の2種類があります。削除できる人が異なるため、該当する種類をご確認ください。" },
      { heading: "現在の口コミ（メッセージでやり取りした参加者の投稿）" },
      { paragraph: "主催者は削除できません。運営でも削除は行いません。" },
      { paragraph: "削除を希望する場合は、投稿した参加者に直接ご相談ください。参加者本人がメッセージの会話画面から自分の口コミを削除できます。" },
      { heading: "旧口コミ（以前の匿名投稿）" },
      { paragraph: "主催者ご自身で削除できます。" },
      { steps: ["主催者アカウントでログインします。", "対象サークルの口コミ一覧を開きます。", "削除したい旧口コミを1件ずつ削除してください。"] }
    ], action: :owner_dashboard },
    { id: 'report', audience: 'all', category: 'review', title: '迷惑行為・不正利用を通報したい', keywords: '違反 ブロック 危険 勧誘 嫌がらせ 安全', content: [
      { heading: "通報・ブロックする" },
      { paragraph: "会話や口コミにある通報機能をご利用ください。必要に応じて会話をブロックすることもできます。" },
      { heading: "画面にアクセスできない場合" },
      { paragraph: "該当する画面にアクセスできない場合は、運営への問い合わせで「迷惑行為・安全上の問題」を選び、対象ページと状況を記入してください。" },
      { heading: "危険が差し迫っている場合" },
      { paragraph: "危険が差し迫っている場合は、警察など適切な機関にも相談してください。" }
    ], action: :messages },
    { id: 'feedback', audience: 'all', category: 'other', title: '運営に改善提案・ご意見を送りたい', keywords: '要望 ご意見箱 意見 機能 追加', content: [
      { paragraph: "ご意見箱では、サービス改善のためのご提案を受け付けています。個別の返信は原則行いません。" },
      { paragraph: "アカウントや不具合について個別の確認が必要な場合は「FAQで解決しない問い合わせ」、迷惑行為は通報をご利用ください。" }
    ], action: :suggestion },
    { id: 'bug', audience: 'all', category: 'other', title: '操作中にエラーが出る・画面が動かない', keywords: '不具合 バグ 保存できない 画像 アップロード', content: [
      { heading: "まず確認すること" },
      { paragraph: "ページを再読み込みし、ブラウザーを更新してもう一度お試しください。保存できない場合は画面の入力エラーを確認してください。" },
      { heading: "改善しない場合" },
      { paragraph: "改善しない場合は、発生した画面のURL、操作の手順、エラー表示、端末・ブラウザーを問い合わせに記入してください。パスワードや認証コードは送らないでください。" }
    ], action: :contact }
  ].map do |article|
    content = article[:content].map do |block|
      block.each_value { |value| value.freeze }
      block.freeze
    end.freeze
    # Keep all headings, paragraphs and steps searchable as plain text.
    article.merge(content: content, body: content.flat_map(&:values).flatten.join("\n\n")).freeze
  end.freeze

  def self.find(id)
    ARTICLES.find { |article| article[:id] == id }
  end

  def self.search(query: '', audience: 'all', category: nil)
    words = query.to_s.unicode_normalize(:nfkc).downcase.split(/[[:space:]]+/).first(8)
    ARTICLES.select do |article|
      text = [article[:title], article[:body], article[:keywords]].join(' ').unicode_normalize(:nfkc).downcase
      (audience == 'all' || article[:audience].in?(['all', audience])) &&
        (category.blank? || article[:category] == category) && words.all? { |word| text.include?(word) }
    end
  end
end
