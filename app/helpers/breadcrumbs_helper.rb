module BreadcrumbsHelper
  # Every HTML page uses this trail, including pages without a Gretel definition.
  BREADCRUMB_SECTIONS = {
    'users' => ['サークル一覧', '/circles'], 'circles' => ['サークル一覧', '/circles'],
    'events' => ['サークル一覧', '/circles'], 'prefectures' => ['サークル一覧', '/circles'],
    'cities' => ['サークル一覧', '/circles'], 'tags' => ['サークル一覧', '/circles'],
    'categories' => ['カテゴリー一覧', '/categories'], 'search' => ['サークル一覧', '/circles'],
    'blogs' => ['ブログ一覧', '/blogs'], 'places' => ['体育館・コート情報', '/places'],
    'place_reviews' => ['体育館・コート情報', '/places'],
    'place_information_reports' => ['体育館・コート情報', '/places'],
    'matches' => ['練習試合', '/match'], 'schedules' => ['イベント開催予定', '/dates'],
    'conversations' => ['メッセージ', '/conversations'], 'help_center' => ['ヘルプセンター', '/faq'],
    'support_requests' => ['ヘルプセンター', '/faq'], 'columns' => ['コラム一覧', '/columns'],
    'exhibitions' => ['出展情報', '/exhibitions'], 'exhibitors' => ['出展情報', '/exhibitions'],
    'presents' => ['プレゼント', '/presents'], 'differences' => ['間違い探しメーカー', '/contents/differences']
  }.freeze

  BREADCRUMB_LABELS = {
    'members' => '参加者', 'admin_users' => '主催者', 'exhibition_groups' => '出展者',
    'webmasters' => 'ウェブマスター', 'attendances' => '出欠管理', 'reviews' => '口コミ・評価',
    'questions' => '質問コーナー', 'event_questions' => '質問一覧', 'opinions' => 'ご意見',
    'links' => 'サークルリンク', 'user_contacts' => 'お問い合わせ', 'member_profiles' => '参加者プロフィール',
    'organizer_profiles' => '主催者プロフィール',
    'member_email_verifications' => 'メールアドレス確認', 'admin_user_email_verifications' => 'メールアドレス確認',
    'backlink_requests' => '公式サイト連携', 'exhibitor_profiles' => '出展者プロフィール',
    'exhibitor_mypages' => '出展者マイページ', 'accounts' => 'アカウント管理',
    'chat_reports' => 'チャット通報', 'no_show_reports' => '欠席申告', 'chat_moderations' => 'チャット管理',
    'account_blocks' => 'ブロック管理', 'invalid_emails' => '無効メールアドレス管理',
    'db_keywords' => 'キーワード管理', 'db_validation_errors' => 'データ検証エラー',
    'db_searches' => 'データ検索', 'dashboard' => '管理トップ'
  }.freeze

  BREADCRUMB_ACTIONS = {
    'index' => '一覧', 'show' => '詳細', 'new' => '新規登録', 'create' => '新規登録',
    'edit' => '編集', 'update' => '編集', 'edit2' => '募集内容の編集', 'update2' => '募集内容の編集',
    'edit3' => '画像の編集', 'update3' => '画像の編集', 'mypage' => 'マイページ',
    'inquiry_settings' => 'お問い合わせ設定', 'update_inquiry_settings' => 'お問い合わせ設定',
    'thanks' => '受付完了', 'confirm' => '確認', 'account_del' => '退会',
    'user_del' => '退会完了', 'member_del' => '退会完了', 'search' => '検索結果',
    'global_search' => '検索結果', 'contact_list' => 'お問い合わせ一覧', 'contact' => 'お問い合わせ',
    'add' => 'サークルの追加登録', 'point' => 'ポイント', 'apply' => '応募',
    'no_index' => '施設一覧', 'show_noindex' => '施設詳細', 'count' => '掲載施設数',
    'login' => 'ログイン', 'line' => 'LINEのURLコピーのやり方',
    'admin_users' => '主催者登録', 'admin_user_list' => '主催者一覧',
    'check_thanks' => '確認完了', 'check_reaction' => 'お問い合わせ確認', 'check_violation' => '違反報告',
    'contact_block' => 'お問い合わせ制限', 'contents' => 'コンテンツ一覧', 'question' => '質問サンプル',
    'all_reviews' => '口コミ・評価一覧', 'secret' => '活動スケジュール'
  }.freeze

  # Only public content routes are eligible; account and management trails remain visual.
  BREADCRUMB_PUBLIC_ACTIONS = {
    'pages' => %w[about rules privacypolicy], 'help_center' => %w[index show],
    'places' => %w[index show event prefecture city search global_search],
    'matches' => %w[index show match event prefecture event_prefecture],
    'schedules' => %w[show dates day today tomorrow this_week next_week],
    'categories' => %w[index category category_prefecture prefecture_index prefecture],
    'tags' => %w[event event_prefecture event_prefecture_city prefecture prefecture_city],
    'users' => %w[prefecture_city_station event_prefecture_city_station line],
    'questions' => %w[index show question], 'reviews' => %w[index all_reviews],
    'columns' => %w[index show], 'differences' => %w[index show contents]
  }.freeze

  def site_breadcrumb_structured_data(items = site_breadcrumb_items)
    return unless public_breadcrumb_structured_data_page? && items.length >= 2
    # Ancestors must have an explicit URL and match the visible navigation.
    return unless items[0...-1].all? { |_, path| path.is_a?(String) && path.start_with?('/') && !path.start_with?('//') }

    {
      '@context' => 'https://schema.org', '@type' => 'BreadcrumbList',
      'itemListElement' => items.each_with_index.map do |(name, path), index|
        item = { '@type' => 'ListItem', 'position' => index + 1, 'name' => name.to_s }
        item['item'] = index < items.length - 1 ? 'https://circle-book.com' + path : breadcrumb_current_url
        item
      end
    }
  end

  def site_breadcrumb_items
    return [['ホーム', nil]] if controller_path == 'home' && action_name == 'index'

    gretel = breadcrumbs.to_a
    items = if gretel.any?
      gretel.map { |link| [link.text, link.url] }
    elsif event_breadcrumb_in_structured_graph?
      [['ホーム', root_path]] + event_listing_breadcrumbs + [[@event_day_title || @event_hub_title, nil]]
    else
      legacy = (1..5).filter_map do |number|
        name = instance_variable_get("@b#{number}_name")
        [name, instance_variable_get("@b#{number}_url").presence] if name.present?
      end
      trail = [['ホーム', root_path]]
      trail += legacy.presence || breadcrumb_parents
      # Legacy definitions with a blank URL already identify the current page.
      if legacy.empty? || (trail.last[1].present? && trail.last[1] != request.path)
        trail << [breadcrumb_page_label, nil]
      end
      trail
    end
    items[0] = ['ホーム', root_path]
    items = items.reject { |name, _| name.blank? }.chunk_while { |a, b| a == b }.map(&:first)
    items.each do |item|
      item[1] = canonical_breadcrumb_path(item[1])
    end
    items.last[1] = nil
    items
  end

  def event_breadcrumb_in_structured_graph?
    controller_path == 'schedules' && %w[dates day today tomorrow this_week next_week].include?(action_name)
  end

  private

  def canonical_breadcrumb_path(path)
    return path unless path.is_a?(String)
    path = path.sub(%r{\A/users(?=/\d+\z|\z)}, '/circles')
    aliases = {}
    if @event.is_a?(Event)
      aliases["/#{@event.ruby}"] = event_path(@event.ruby)
      if @prefecture.is_a?(Prefecture)
        aliases["/#{@event.ruby}/#{@prefecture.kana}"] = event_prefecture_path(@event.ruby, @prefecture.kana)
        if @city.is_a?(City)
          aliases["/#{@event.ruby}/#{@prefecture.kana}/#{@city.city_kana}"] = event_prefecture_city_path(@event.ruby, @prefecture.kana, @city.city_kana)
        end
      end
    end
    if @prefecture.is_a?(Prefecture) && @city.is_a?(City)
      aliases["/prefectures/#{@prefecture.kana}/#{@city.city_kana}"] = prefecture_city_path(@prefecture.kana, @city.city_kana)
    end
    aliases["/categories/#{@category.name}"] = "/categories/#{@category.kana}" if @category.is_a?(Category)
    aliases.fetch(path, path)
  end

  def breadcrumb_current_url
    canonical = meta_tags[:canonical]
    uri = URI.parse(canonical.is_a?(String) ? canonical : request.fullpath)
    query = Rack::Utils.parse_nested_query(uri.query).reject do |key, _|
      key == 'sort' || key.start_with?('utm_') || %w[gclid fbclid].include?(key)
    end
    query.delete('page') if query['page'] == '1'
    'https://circle-book.com' + uri.path + (query.present? ? '?' + query.to_query : '')
  end

  def public_breadcrumb_structured_data_page?
    return false unless request.get?
    return false if webmaster? || meta_tags[:noindex] || response.headers['X-Robots-Tag'].to_s.include?('noindex')
    if controller_path.start_with?('circles/', 'blogs/', 'exhibitions/', 'presents/')
      return %w[index show landing].include?(action_name)
    end
    BREADCRUMB_PUBLIC_ACTIONS.fetch(controller_path, []).include?(action_name)
  end

  def breadcrumb_parents
    if controller_path.start_with?('super_admin/', 'webmasters/') ||
        %w[account_blocks invalid_emails db_keywords db_validation_errors db_searches].include?(controller_path)
      parents = [['管理トップ', '/webmaster']]
      section = controller_path.split('/').last
      parents << [BREADCRUMB_LABELS[section] || BREADCRUMB_SECTIONS.dig(section, 0), "/#{controller_path}"] if controller_path.start_with?('super_admin/') && action_name != 'index'
      return parents.reject { |_, path| path == request.path }
    end
    return [['ヘルプセンター', '/faq']] if controller_path == 'help_center' && action_name != 'index'
    return [] if controller_path == 'pages'

    section = if controller_path.start_with?('blogs/')
      BREADCRUMB_SECTIONS['blogs']
    elsif controller_path.start_with?('exhibitions/')
      BREADCRUMB_SECTIONS['exhibitions']
    else
      BREADCRUMB_SECTIONS[controller_path.split('/').last]
    end
    parents = section && section[1] != request.path ? [section.dup] : []
    # Only User objects represent circles; account objects must not become circle links.
    if @user.is_a?(User) && @user.persisted? &&
        %w[users schedules questions reviews opinions user_contacts links matches attendances backlink_requests].include?(controller_path)
      parents << [@user.name, circle_path(@user)]
    end
    parents
  end

  def breadcrumb_page_label
    parts = controller_path.split('/')
    if %w[sessions registrations passwords confirmations unlocks].include?(parts.last)
      account = BREADCRUMB_LABELS.fetch(parts.first, 'アカウント')
      form = { 'sessions' => 'ログイン', 'registrations' => (%w[edit update].include?(action_name) ? 'アカウント設定' : '新規登録'),
               'passwords' => 'パスワード再設定', 'confirmations' => 'メールアドレス確認', 'unlocks' => 'ロック解除' }.fetch(parts.last)
      return "#{account}の#{form}"
    end
    return '退会' if parts.first == 'unsubscribe'
    return @article[:title] if controller_path == 'help_center' && @article
    return 'お問い合わせ設定' if %w[inquiry_settings update_inquiry_settings].include?(action_name)

    title = meta_tags[:title]
    return title.to_s if title.present? && !title.is_a?(Symbol)

    section = parts.last
    label = BREADCRUMB_LABELS[section] || BREADCRUMB_SECTIONS.dig(section, 0) || 'ページ'
    action = BREADCRUMB_ACTIONS[action_name]
    %w[index show].include?(action_name) ? label : [label, action || '確認'].join('の')
  end
end
