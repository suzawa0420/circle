require 'test_helper'
require_relative '../support/chat_records'

class ParticipantAccountsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    post member_session_path, params: { member: { email: @member.email, password: 'test-password-123' } }
  end

  test 'participant auth forms render with the shared account design' do
    delete destroy_member_session_path
    [new_member_session_path, new_member_registration_path, new_member_password_path].each do |path|
      get path
      assert_response :success
      assert_select '.participant-form', count: 1
    end
  end

  test 'birthday changes decade without exposing the birthday publicly' do
    @member.update!(date_of_birth: '1986-10-02', profile: '週末のスポーツが好きです。', prefecture: @circle.prefecture, events: [@circle.event])
    assert_equal '30代', @member.age_group(on: Date.new(2026, 10, 1))
    assert_equal '40代', @member.age_group(on: Date.new(2026, 10, 2))
    get member_profile_path(@member)
    assert_response :success
    assert_includes response.body, @member.age_group
    assert_not_includes response.body, '1986-10-02'
    assert_select '.public-profile-identity h1', text: /参加者さくら/
    assert_select '.public-profile-meta', text: /東京都/
    assert_select '.public-profile-bio', text: /週末のスポーツが好きです。/
    assert_select '.public-profile-interests span', text: 'バスケ'
    assert_select '.public-profile-score', count: 0
    @member.date_of_birth = Date.current + 1
    assert_not @member.valid?
    @member.date_of_birth = 'not-a-date'
    assert_not @member.valid?
    @member.date_of_birth = nil
    assert @member.valid?
    assert_nil @member.age_group
  end

  test 'profile saves several interests and private birthday but rejects residential and account fields' do
    extra = Event.create!(name: 'テニス', ruby: 'account-tennis', category: @circle.category, order: '2')
    get edit_member_path(@member)
    assert_response :success
    assert_select 'input[name="member[event_ids][]"][type=checkbox]', count: 2
    assert_select 'input[name="member[date_of_birth]"]', count: 1
    assert_select '[name="member[living_address]"]', count: 0
    assert_select '[name="member[age]"]', count: 0
    patch member_path(@member), params: { member: { nickname: '更新した参加者', prefecture_id: @circle.prefecture_id,
      date_of_birth: '1990-05-06', event_ids: ['', @circle.event_id, extra.id], living_address: '非保存', age: '90代', email: 'changed@example.test' } }
    assert_redirected_to member_path(@member)
    @member.reload
    assert_equal Date.new(1990, 5, 6), @member.date_of_birth
    assert_equal [@circle.event_id, extra.id].sort, @member.event_ids.sort
    assert_nil @member.living_address
    assert_nil @member.age
    assert_equal 'chat-member@example.test', @member.email
    patch member_path(@member), params: { member: { nickname: '', date_of_birth: '2099-01-01', event_ids: ['', extra.id] } }
    assert_response :unprocessable_entity
    assert_select 'input[name="member[event_ids][]"][type=checkbox]', count: 2
    assert_equal Date.new(1990, 5, 6), @member.reload.date_of_birth
    assert_equal [@circle.event_id, extra.id].sort, @member.event_ids.sort
  end

  test 'self introduction requires Japanese kana and keeps invalid input for correction' do
    get edit_member_path(@member)
    assert_select '#profile-language-help', text: /必ず日本語でお書きください/
    assert_select 'textarea[aria-describedby="profile-language-help profile-privacy-help"]'
    ['台灣外送茶推薦服務', 'Hello, please contact me', '<span title="あ">中文宣傳</span>'].each do |profile|
      patch member_path(@member), params: { member: { profile: profile, prefecture_id: @circle.prefecture_id, event_ids: [@circle.event_id] } }
      assert_response :unprocessable_entity
      assert_select '[role=alert]', text: /必ず日本語/
      assert_nil @member.reload.profile
    end
    ['週末に運動したいです。', 'よろしくおねがいします。', 'テニス', 'ﾃﾆｽ', ''].each do |profile|
      patch member_path(@member), params: { member: { profile: profile, prefecture_id: @circle.prefecture_id, event_ids: [@circle.event_id] } }
      assert_redirected_to member_path(@member)
      assert_equal profile, @member.reload.profile
    end
  end

  test 'legacy non Japanese introductions cannot send messages until corrected' do
    @member.update_column(:profile, '台灣外送茶推薦服務')
    get new_user_conversation_path(@circle)
    assert_redirected_to edit_member_path(@member)
    assert_no_difference 'ChatMessage.count' do
      post message_conversation_path(@conversation), params: { message: { body: '参加できますか？' } }
    end
    assert_redirected_to edit_member_path(@member)
    assert_raises(Conversation::NotAllowed) { @conversation.send_message!('member', '参加希望です。') }
    get conversation_path(@conversation)
    assert_response :success
    assert_select 'a', text: '自己紹介を修正する'
    assert_select '.chat-compose-form', count: 0
    @member.reload.update!(profile: '週末に参加したいです。')
    assert_difference 'ChatMessage.count', 1 do
      post message_conversation_path(@conversation), params: { message: { body: '参加できますか？' } }
    end
    assert_redirected_to conversation_path(@conversation)
  end

  test 'private pages reject other participants and favorites are visible on own dashboard' do
    @member.bookmarks.create!(user: @circle)
    get member_path(@member)
    assert_response :success
    assert_includes response.headers['Cache-Control'], 'no-store'
    assert_select '.participant-circle', text: /チャット検証サークル/
    get edit_member_registration_path
    assert_response :success
    assert_select 'input[name="member[current_password]"]'
    get member_path(@other_member)
    assert_response :forbidden
    get edit_member_path(@other_member)
    assert_response :forbidden
    patch member_path(@other_member), params: { member: { date_of_birth: '1990-01-01' } }
    assert_response :forbidden
    assert_nil @other_member.reload.date_of_birth
  end

  test 'preparation cards follow saved interests without requiring a prefecture' do
    basketball = Column.create!(title: 'バスケの持ち物', description: '靴と服装を確認しましょう。', text: '参加の準備', publication_status: 'published', audience: 'participant', event: @circle.event, affiliate: true)
    tennis = Event.create!(name: 'テニス', ruby: 'guide-tennis', category: @circle.category, order: '2')
    shared = Column.create!(title: 'テニスの準備', text: '参加の準備', publication_status: 'published', audience: 'all', event: tennis)
    Column.create!(title: '主催者用', text: '備品', publication_status: 'published', audience: 'organizer', event: @circle.event)
    Column.create!(title: '下書き', audience: 'participant', event: @circle.event)
    Column.create!(title: '全ジャンルの案内', text: '案内', publication_status: 'published', audience: 'participant')
    @member.events = [@circle.event]
    get member_path(@member)
    assert_response :success
    assert_nil @member.prefecture_id
    assert_select '.column-guide-links__link', count: 1
    assert_select ".column-guide-links__link[href='#{column_path(basketball)}']", text: /バスケの持ち物.*広告を含む記事/
    assert_select '.column-guide-links__description', text: '靴と服装を確認しましょう。'
    assert_select '.column-guide-links__link img', count: 0
    @member.events = [@circle.event, tennis]
    get member_path(@member)
    assert_select '.column-guide-links__link', count: 2
    assert_select ".column-guide-links__link[href='#{column_path(shared)}']"
    @member.events = [tennis]
    get member_path(@member)
    assert_select ".column-guide-links__link[href='#{column_path(basketball)}']", count: 0
    @member.events = []
    get member_path(@member)
    assert_select '.column-guide-links', count: 0
    get member_profile_path(@member)
    assert_select '.column-guide-links', count: 0
  end

  test 'preparation cards are bounded and keep article covers decorative inside the link' do
    @member.events = [@circle.event]
    4.times { |i| Column.create!(title: "準備#{i}", text: '参加前の確認', publication_status: 'published', audience: 'participant', event: @circle.event) }
    article = Column.order(:id).last
    article.update_column(:image, 'guide-cover.png')
    get member_path(@member)
    assert_select '.column-guide-links__link', count: 3
    assert_select ".column-guide-links__link[href='#{column_path(article)}'] img[alt=''][loading='lazy'][width='96'][height='80']"
    assert_select '.column-guide-links__link a', count: 0
  end
  test 'public member rating uses shared stars and sentiment classes instead of a five point fraction' do
    accept_conversation
    @conversation.submit_review!('owner', owner_evaluation.merge(score: 1))
    @conversation.submit_review!('member', member_evaluation)
    get member_profile_path(@member)
    assert_response :success
    assert_select '.public-profile-score .star svg.orange', count: 5
    assert_select '.public-profile-score strong', text: '5.0'
    assert_select '.public-profile-score', text: /5.0.*1件/
    assert_select '.public-profile-score', text: %r{/ 5}, count: 0
    assert_select '.public-profile-rating-counts .profile-expression--positive', count: 1
    assert_select '.public-profile-rating-counts .profile-expression--negative', count: 1
    assert_select '.public-profile-review__rating.review-sentiment--positive .profile-expression--positive', count: 1
  end

end
