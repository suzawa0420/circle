require 'test_helper'

class RuntimeUpgradeTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  test 'public pages and all account forms render on the upgraded runtime' do
    %w[/ /health /privacypolicy /admin_users/sign_in /members/sign_in /exhibition_groups/sign_in /admin_users/sign_up /members/sign_up].each do |path|
      get path
      assert_response :success, "#{path}: #{response.status}"
    end
  end

  test 'footer does not show the contact mail link' do
    get '/'
    assert_response :success
    assert_select '.breadcrumbs_wrapper', count: 1
    assert_select 'footer .breadcrumbs_wrapper', count: 1
    assert_not_includes response.body, 'mailto:circlebook26@gmail.com?subject=【お問い合わせ】サークルブック'
  end

  test 'public pages load the new GTM container and AdSense code' do
    %w[/ /privacypolicy].each do |path|
      get path
      assert_response :success
      assert_equal 2, response.body.scan('GTM-MD88D9HB').size
      assert_not_includes response.body, 'GTM-WZ5RS5L'
      assert_match(/<head>\s*<!-- Google Tag Manager -->/, response.body)
      assert_match(/<body[^>]*>\s*<!-- Google Tag Manager \(noscript\) -->/, response.body)
      assert_not_includes response.body, '/gtag/js'
      assert_not_includes response.body, "gtag('config'"
      assert_select 'head script[src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=ca-pub-7744112029922449"]', count: 1
      assert_includes response.body, 'crossorigin="anonymous"'
      assert_not_includes response.body, 'data-ad-client'
    end
  end

  test 'AdMax has one public placement and does not run on account forms or policy pages' do
    get '/'
    assert_response :success
    assert_select '.admax-switch[data-admax-id="8c416c3bb0ba1614046f01a5e3f43ca0"]', count: 1
    assert_select 'script[src="https://adm.shinobi.jp/st/t.js"][async]', count: 1
    assert_select 'meta[name="turbolinks-visit-control"][content="reload"]', count: 1
    %w[/admin_users/sign_in /admin_users/sign_up /privacypolicy].each do |path|
      get path
      assert_response :success
      assert_select '.admax-switch', count: 0
    end
  end

  test 'populated circle listings and profile render' do
    category = Category.create!(name: '球技', kana: 'ball-sports', order: '1')
    event = Event.create!(name: 'バスケ', ruby: 'basketball', category: category, order: '1')
    prefecture = Prefecture.create!(name: '東京都', kana: 'tokyo', order: '1', sort: 1)
    owner = AdminUser.create!(email: 'runtime-owner@example.test', password: 'test-password-123')
    circle = User.create!(name: '更新検証サークル', appeal: '地域で定期的に練習しています。初心者も経験者も歓迎します。' * 6, event: event,
                          area: '世田谷区周辺', schedule: '毎週土曜日',
                          prefecture: prefecture, category: category, admin_user: owner,
                          switch: '募集中', recruitment: '初心者歓迎', last_post: Time.current.to_s)
    %W[/ /circles /circles/#{circle.id} /categories/ball-sports /circles/search/バスケ].each do |path|
      get URI::DEFAULT_PARSER.escape(path)
      follow_redirect! if response.redirect? && path.start_with?('/circles/search/')
      assert_response :success, "#{path}: #{response.status}"
    end

    %W[/users/#{circle.id}/questions /users/#{circle.id}/question?sample=first].each do |path|
      get path
      assert_response :success
    end

    get circle_path(circle)
    assert_response :success
    assert_select '.breadcrumbs_wrapper', count: 1
    assert_select 'footer .breadcrumbs_wrapper', count: 1
    assert_select 'footer .breadcrumbs', text: /更新検証サークル/

    get '/categories/ball-sports'
    assert_response :success
    assert_select '.breadcrumbs_wrapper', count: 1
    assert_select 'footer .breadcrumbs_wrapper', count: 1
    assert_select 'footer .breadcrumbs', text: /球技/

    assert_includes User.ransack(name_cont: '更新検証').result, circle
    assert_not_includes User.ransackable_attributes, 'password'
    assert_not_includes User.ransackable_attributes, 'email'
    assert_empty User.ransackable_associations
  end

  test 'suspected solicitation circles stay public with warnings while shadow banned circles stay hidden' do
    category = Category.create!(name: '球技', kana: 'ball-sports', order: '1')
    event = Event.create!(name: 'バスケ', ruby: 'basketball', category: category, order: '1')
    prefecture = Prefecture.create!(name: '神奈川県', kana: 'kanagawa', order: '14', sort: 14)
    owners = {
      network_business: AdminUser.create!(email: 'network-warning@example.test', password: 'test-password-123', check: 1),
      religion: AdminUser.create!(email: 'religion-warning@example.test', password: 'test-password-123', check: 2),
      shadow_banned: AdminUser.create!(email: 'shadow-banned@example.test', password: 'test-password-123', check: 3)
    }
    common_attributes = {
      event: event, prefecture: prefecture, category: category,
      switch: '募集中', area: '横浜市内', schedule: '毎週土曜日',
      appeal: '地域で楽しく活動しています。初心者も経験者も歓迎します。' * 6,
      last_post: Time.current.to_s
    }
    circles = {
      network_business: User.create!(**common_attributes, admin_user: owners[:network_business], name: 'ネットワーク注意サークル'),
      religion: User.create!(**common_attributes, admin_user: owners[:religion], name: '宗教注意サークル'),
      shadow_banned: User.create!(**common_attributes, admin_user: owners[:shadow_banned], name: '非表示サークル')
    }

    get '/events/basketball/prefectures/kanagawa'
    assert_response :success
    assert_includes response.body, circles[:network_business].name
    assert_includes response.body, circles[:religion].name
    assert_not_includes response.body, circles[:shadow_banned].name

    get circle_path(circles[:network_business])
    assert_response :success
    assert_includes response.body, '【ネットワークビジネス（マルチ商法）】の勧誘を目的としたサークルの可能性があります。'
    assert_not_includes response.body, 'このサークルは一般には公開されていません。'

    get circle_path(circles[:religion])
    assert_response :success
    assert_includes response.body, '【宗教】の勧誘を目的としたサークルの可能性があります。'
    assert_not_includes response.body, 'このサークルは一般には公開されていません。'

    assert_raises(ActiveRecord::RecordNotFound) do
      get circle_path(circles[:shadow_banned])
    end
  end

  test 'tag routes return 404 for unknown event and prefecture slugs' do
    previous_show_exceptions = Rails.application.env_config['action_dispatch.show_exceptions']
    Rails.application.env_config['action_dispatch.show_exceptions'] = :rescuable
    tag = Tag.create!(name: '検証タグ', order: '1')
    category = Category.create!(name: '検証分類', kana: 'runtime-tag-category', order: '1')
    event = Event.create!(name: '検証競技', ruby: 'runtime-valid-event', order: '1', category: category)
    prefecture = Prefecture.create!(name: '検証県', kana: 'runtime-valid-prefecture', order: '1', sort: 1)
    %W[/runtime-missing-event/#{prefecture.kana}/tag/#{tag.id}
       /#{event.ruby}/runtime-missing-prefecture/tag/#{tag.id}
       /prefectures/runtime-missing-prefecture/tag/#{tag.id}
       /#{event.ruby}/#{prefecture.kana}/runtime-missing-city/tag/#{tag.id}
       /prefectures/#{prefecture.kana}/runtime-missing-city/tag/#{tag.id}].each do |path|
      get path
      assert_response :not_found, "#{path}: #{response.status}"
    end
  ensure
    Rails.application.env_config['action_dispatch.show_exceptions'] = previous_show_exceptions
  end

  test 'anonymous member profile requests require registration before accessing the member' do
    %w[/members/987654321 /members/987654321/edit].each do |path|
      get path
      assert_redirected_to new_member_registration_path
    end
    assert_no_difference('Member.count') do
      patch '/members/987654321', params: { member: { nickname: 'unauthorized' } }
      assert_redirected_to new_member_registration_path
    end
  end

  test 'member can sign in and sign out with the existing password format' do
    member = Member.create!(email: 'runtime-member@example.test', password: 'test-password-123', nickname: '検証会員')
    assert member.valid_password?('test-password-123')
    post '/members/sign_in', params: { member: { email: member.email, password: 'test-password-123' } }
    assert_response :redirect
    assert_equal member.id, session['warden.user.member.key'].first.first
    delete '/members/sign_out'
    assert_response :redirect
    assert_nil session['warden.user.member.key']
  end

  test 'uploaded image is processed and a cache version is retained' do
    require 'base64'
    require 'tempfile'
    file = Tempfile.new(['runtime-image', '.gif'])
    file.binmode
    file.write(Base64.decode64('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'))
    file.rewind
    uploader = ImageUploader.new(User.new(id: 987654321, updated_at: Time.utc(2026, 9, 26)), :pic_profile)
    uploader.store!(file)
    assert File.exist?(uploader.path)
    assert_equal 'JPEG', MiniMagick::Image.open(uploader.path).type
    assert_equal '.jpg', File.extname(uploader.path)
    assert_match(/v=\d+/, uploader.url)
    assert_equal [1, 1], MiniMagick::Image.open(uploader.path).dimensions
  ensure
    uploader&.remove!
    file&.close!
  end

  test 'unsupported upload extension remains rejected' do
    require 'tempfile'
    file = Tempfile.new(['runtime-upload', '.html'])
    file.write('<html>not an image</html>')
    file.rewind
    uploader = ImageUploader.new(User.new(id: 987654321), :pic_profile)
    assert_raises(CarrierWave::IntegrityError) { uploader.cache!(file) }
  ensure
    file&.close!
  end

  test 'invalid date remains a validation error' do
    schedule = Schedule.new(day: 'not-a-date', title: 'テスト', venue: '体育館')
    assert_not schedule.valid?
    assert schedule.errors.added?(:day, :invalid)
  end

  test 'legacy circle with empty recruitment still renders in listings' do
    circle = runtime_circle
    circle.update_column(:recruitment, nil)
    get '/circles'
    assert_response :success
    assert_includes response.body, circle.name
  end

  test 'anonymous management requests require admin sign in without changing schedules' do
    circle = runtime_circle
    schedule = circle.schedules.create!(day: Date.tomorrow.to_s, title: '検証予定', venue: '検証会場')
    %W[/users/#{circle.id}/edit /users/#{circle.id}/contact_list
       /users/#{circle.id}/schedules/new /users/#{circle.id}/schedules/#{schedule.id}/edit].each do |path|
      get path
      assert_redirected_to new_admin_user_session_path
    end
    assert_no_difference('Schedule.count') do
      post "/users/#{circle.id}/schedules", params: { schedule: { title: '無認証', day: Date.tomorrow.to_s, venue: '検証会場' } }
      assert_redirected_to new_admin_user_session_path
      delete "/users/#{circle.id}/schedules/#{schedule.id}"
      assert_redirected_to new_admin_user_session_path
    end
  end

  test 'owner can delete a schedule and persist recalculated points' do
    circle = runtime_circle
    circle.update!(user_time: Time.current.to_s, cb_point: 10)
    schedule = circle.schedules.create!(day: Date.tomorrow.to_s, title: '検証予定', venue: '検証会場')
    post '/admin_users/sign_in', params: { admin_user: { email: circle.admin_user.email, password: 'test-password-123' } }
    assert_response :redirect
    assert_difference('Schedule.count', -1) do
      delete "/users/#{circle.id}/schedules/#{schedule.id}"
      assert_redirected_to user_schedules_path(circle)
    end
    assert_equal 0, circle.reload.cb_point
  end

  test 'invalid city and prefecture URLs do not render nil records' do
    circle = runtime_circle
    previous_show_exceptions = Rails.application.env_config['action_dispatch.show_exceptions']
    Rails.application.env_config['action_dispatch.show_exceptions'] = :rescuable
    get "/prefectures/#{circle.prefecture.kana}/cities/runtime-missing-city"
    assert_response :not_found
    get '/prefectures/runtime-missing-prefecture/cities/runtime-missing-city'
    assert_response :not_found
    city = circle.prefecture.cities.create!(name: '検証市', city_kana: 'runtime-valid-city')
    get "/events/#{circle.event.ruby}/prefectures/runtime-missing-prefecture/cities/#{city.city_kana}"
    assert_response :not_found
  ensure
    Rails.application.env_config['action_dispatch.show_exceptions'] = previous_show_exceptions
  end

  test 'empty facility searches return to the listing without recording a search' do
    circle = runtime_circle
    [nil, '', '   ', { invalid: 'value' }].each do |keyword|
      assert_no_difference('DbSearch.count') do
        get "/places/#{circle.event.ruby}/search", params: { kw: keyword }
        assert_redirected_to "/places/#{circle.event.ruby}"
      end
    end
  end

  test 'facility URLs return 404 for unknown or mismatched regions' do
    circle = runtime_circle
    city = circle.prefecture.cities.create!(name: '施設検証市', city_kana: 'facility-valid-city')
    other_prefecture = Prefecture.create!(name: '別県', kana: 'facility-other-prefecture', sort: 2)
    place = Place.create!(name: '施設検証体育館', prefecture: circle.prefecture, city: city,
                          events: [circle.event], tag: '体育館', address: '検証住所')
    previous_show_exceptions = Rails.application.env_config['action_dispatch.show_exceptions']
    Rails.application.env_config['action_dispatch.show_exceptions'] = :rescuable
    %W[/places/missing-facility-event
       /places/#{circle.event.ruby}/missing-facility-prefecture
       /places/#{circle.event.ruby}/#{circle.prefecture.kana}/missing-facility-city
       /places/#{circle.event.ruby}/missing-facility-prefecture/#{city.city_kana}/#{place.id}
       /places/#{circle.event.ruby}/#{circle.prefecture.kana}/missing-facility-city/#{place.id}
       /places/#{circle.event.ruby}/#{other_prefecture.kana}/#{city.city_kana}/#{place.id}
       /places/all/missing-facility-prefecture/#{city.city_kana}/#{place.id}].each do |path|
      get path
      assert_response :not_found, "#{path}: #{response.status}"
    end
    get "/places/#{circle.event.ruby}/#{circle.prefecture.kana}/#{city.city_kana}/#{place.id}"
    assert_response :success
  ensure
    Rails.application.env_config['action_dispatch.show_exceptions'] = previous_show_exceptions
  end

  private

  def runtime_circle
    category = Category.create!(name: '検証分類', kana: 'runtime-safety-category', order: '1')
    event = Event.create!(name: '検証競技', ruby: 'runtime-safety-event', category: category, order: '1')
    prefecture = Prefecture.create!(name: '検証県', kana: 'runtime-safety-prefecture', order: '1', sort: 1)
    owner = AdminUser.create!(email: 'runtime-safety-owner@example.test', password: 'test-password-123')
    User.create!(name: '実データ条件検証サークル', appeal: '地域で定期的に活動しています。参加をご希望の方はご連絡ください。' * 6, event: event,
                 area: '東京都内', schedule: '毎週日曜日',
                 prefecture: prefecture, category: category, admin_user: owner,
                 switch: '募集中', recruitment: '初心者歓迎', last_post: Time.current.to_s)
  end

end
