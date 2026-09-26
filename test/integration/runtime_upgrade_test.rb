require 'test_helper'

class RuntimeUpgradeTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  test 'public pages and all account forms render on the upgraded runtime' do
    %w[/ /health /privacypolicy /admin_users/sign_in /members/sign_in /exhibition_groups/sign_in /admin_users/sign_up /members/sign_up].each do |path|
      get path
      assert_response :success, "#{path}: #{response.status}"
    end
  end

  test 'populated circle listings and profile render' do
    category = Category.create!(name: '球技', kana: 'ball-sports', order: '1')
    event = Event.create!(name: 'バスケ', ruby: 'basketball', category: category, order: '1')
    prefecture = Prefecture.create!(name: '東京都', kana: 'tokyo', order: '1', sort: 1)
    owner = AdminUser.create!(email: 'runtime-owner@example.test', password: 'test-password-123')
    circle = User.create!(name: '更新検証サークル', appeal: '楽しく活動します', event: event,
                          prefecture: prefecture, category: category, admin_user: owner,
                          switch: '募集中', recruitment: '初心者歓迎', last_post: Time.current.to_s)
    %W[/ /circles /circles/#{circle.id} /categories/ball-sports /circles/search/バスケ].each do |path|
      get URI::DEFAULT_PARSER.escape(path)
      follow_redirect! if response.redirect? && path.start_with?('/circles/search/')
      assert_response :success, "#{path}: #{response.status}"
    end
    assert_includes User.ransack(name_cont: '更新検証').result, circle
    assert_not_includes User.ransackable_attributes, 'password'
    assert_not_includes User.ransackable_attributes, 'email'
    assert_empty User.ransackable_associations
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
end
