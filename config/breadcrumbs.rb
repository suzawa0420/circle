crumb :root do
  link "TOP", root_path
end

# circle
crumb :circle_index do
  link "サークル一覧", circles_path
  parent :root
end

crumb :circle_search_index do |q|
  link "「#{q}」のサークル検索結果", circles_search_index_path
  parent :root
end

crumb :circle_search_show do |q|
  link "「#{q}」のサークル検索結果", circles_search_path(q)
  parent :root
end

  ## events配下
  crumb :event_show do |event|
    link "#{event.name}", event_path(event.ruby)
    parent :circle_index
  end

  crumb :event_prefecture_show do |event, prefecture|
    link "#{prefecture.name}", event_prefecture_path(event.ruby, prefecture.kana)
    parent :event_show, event
  end

  crumb :event_prefecture_city do |event, prefecture, city|
    link "#{city.name}", event_prefecture_city_path(event.ruby, prefecture.kana, city.city_kana)
    parent :event_prefecture_show, event, prefecture
  end


  ## サークル詳細ページ
  crumb :circle_show do |user|
    link "#{user.name}", circle_path(user)
    parent :event_prefecture_show, user.event, user.prefecture
  end

  crumb :circle_blog_index do |user|
    link "ブログ一覧", circle_blogs_path(user.id)
    parent :circle_show, user
  end

  ## prefectures配下
  crumb :prefecture_show do |prefecture|
    link "#{prefecture.name}", prefecture_path(prefecture.kana)
    parent :circle_index
  end

  crumb :prefecture_city_show do |prefecture, city|
    link "#{city.name}", prefecture_city_path(prefecture.kana, city.city_kana)
    parent :prefecture_show, prefecture
  end


  ## tags配下
  crumb :tag_show do |tag|
    link "#{tag.name}", tag_path(tag.id)
    parent :circle_index
  end

# present
crumb :present_index do
  link "プレゼント", presents_path
  parent :root
end

# blog
crumb :blog_index do
  link "ブログ一覧", blogs_path
  parent :root
end

  ## events配下
  crumb :blog_event_show do |event|
    link "#{event.name}", blogs_event_path(event.ruby)
    parent :blog_index
  end

  crumb :blog_event_prefecture_show do |event, prefecture|
    link "#{prefecture.name}", blogs_event_prefecture_path(event.ruby, prefecture.kana)
    parent :blog_event_show, event
  end

  ## ブログ詳細ページ
  crumb :blog_show do |blog|
    link "#{blog.title}", circle_blog_path(blog.user, blog)
    parent :blog_event_prefecture_show, blog.user.event, blog.user.prefecture
  end

  ## prefectures配下
  crumb :blog_prefecture_show do |prefecture|
    link "#{prefecture.name}", blogs_prefecture_path(prefecture.kana)
    parent :blog_index
  end