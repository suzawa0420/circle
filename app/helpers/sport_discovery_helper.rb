module SportDiscoveryHelper
  SPORT_GUIDES = {
    'tennis' => '硬式テニスの仲間を探せます。初心者の受け入れ、練習と試合の割合、開催コート、ラケットの持参・貸出、参加費を確認しましょう。ソフトテニスの募集は別の一覧から探せます。',
    'camping' => 'キャンプを一緒に楽しむ仲間の募集です。初心者・一人参加の受け入れ、テントや調理道具の貸出、集合・出発場所、日帰り・宿泊、交通費を含む参加費を確認して選びましょう。',
    'gathering' => 'カフェ会・交流会の参加先を探せます。参加年代、人数、会場、飲食代を含む参加費、初参加の受け入れを確認して、自分に合う集まりを選びましょう。',
    'futsal' => 'フットサルを一緒に楽しむ仲間の募集です。初心者の受け入れ、経験者との組み分け、男女の募集条件、開催コート、シューズと参加費を確認しましょう。',
    'volleyball' => 'バレーボールの仲間を探せます。6人制・9人制、男女混合などの活動内容、経験の目安、ネットの高さ、練習場所と参加費を確認して選びましょう。',
    'karate' => '空手の仲間・体験参加者の募集です。流派や稽古内容、大人・子どもの対象、初心者の受け入れ、体験費用を確認して選びましょう。',
    'handicraft' => '手芸・ハンドメイドを一緒に楽しむ仲間の募集です。編み物やアクセサリーなどの制作内容、材料・道具の持参、参加費を確認しましょう。',
    'karaoke' => 'カラオケを楽しむ仲間の募集です。曲のジャンル、参加年代、開催人数、会場と料金を確認して、自分に合う集まりを探しましょう。',
    'soft-tennis' => 'ソフトテニス（軟式テニス）の募集です。硬式テニスと区別し、経験の目安・ラケット貸出・開催コートを確認して選びましょう。',
    'pickleball' => 'ピックルボールの募集です。初めての方は体験参加やパドル貸出の有無、開催施設と次回日程を確認しましょう。',
    'ski' => 'スキーの募集です。集合・出発場所と滑るゲレンデ、日帰り・宿泊、参加レベルや費用を確認しましょう。',
    'road-bike' => 'サイクリング・ポタリングなど、活動スタイルと走行距離・ペース・集合場所を確認して仲間を探しましょう。',
    'mountain' => 'ハイキング・低山登山など、活動内容と難易度・集合場所・持ち物を確認して参加先を選びましょう。',
    'running' => 'ジョギング・マラソンなど、目的や走る距離・ペースが合う仲間を探しましょう。'
  }.freeze

  def related_sport_links(event, prefecture = nil)
    slugs = case event&.ruby
            when 'tennis', 'soft-tennis', 'pickleball' then %w[tennis soft-tennis pickleball]
            when 'ski', 'snow-board' then %w[ski snow-board]
            else []
            end
    Event.where(ruby: slugs).where.not(id: event&.id).order(:order).filter_map do |sport|
      users = User.publicly_visible.for_event(sport.id).where(switch: '募集中')
      users = users.where_pref(prefecture.id) if prefecture
      next unless users.exists?
      [sport.name, CircleFilterLanding.path(event: sport, prefecture: prefecture)]
    end
  end

  def sport_populated_regions(event)
    users = User.publicly_visible.for_event(event.id).where(switch: '募集中')
    Prefecture.where(id: users.select(:prefecture_id)).or(Prefecture.where(id: users.select(:prefecture_sub_id))).order(:order)
  end

  def region_discovery_sports(prefecture)
    users = User.publicly_visible.where_pref(prefecture.id).where(switch: '募集中')
    ids = users.select(:event_id)
    Event.where(id: ids).where.not(ruby: [nil, '', 'nil']).order(:order, :id)
  end
end
