module HomeHelper
  def home_services
    [
      { key: "circles", title: "サークルを探す", icon: "users", description: "好きな活動の仲間を見つけよう", label: "人気順", path: circles_path, more: "サークル一覧へ" },
      { key: "events", title: "イベントを探す", icon: "calendar-days", description: "今日参加できる活動をチェック", label: "今日 #{Date.current.strftime('%-m/%-d')}（#{SchedulesHelper::SCHEDULE_WEEKDAYS[Date.current.wday]}）", path: dates_path, more: "イベント一覧へ" },
      { key: "blogs", title: "ブログを探す", icon: "book-open", description: "活動の様子や雰囲気をのぞいてみよう", label: "最新更新", path: blogs_path, more: "活動ブログ一覧へ" },
      { key: "matches", title: "対戦相手を探す", icon: "trophy", description: "練習試合や交流戦の相手を見つけよう", label: "最新更新", path: matches_path, more: "対戦相手募集一覧へ" },
      { key: "places", title: "コート体育館を探す", icon: "landmark", description: "活動にぴったりの場所を探そう", label: "施設情報", path: "/places", more: "コート・体育館一覧へ" }
    ]
  end
end
