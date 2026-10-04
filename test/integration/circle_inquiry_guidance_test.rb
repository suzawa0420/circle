require 'test_helper'
require_relative '../support/chat_records'

class CircleInquiryGuidanceTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    @circle.update!(template: "お問い合わせありがとうございます。\n・年代\n・経験\n・参加希望日")
    4.times do |i|
      @circle.schedules.create!(title: "活動#{i + 1}", venue: '公開体育館', member_venue: '参加確定者だけの集合場所',
                               day: (Date.current + i + 1).to_s)
    end
    @circle.schedules.create!(title: '過去の活動', venue: '体育館', day: Date.yesterday.to_s)
  end

  test 'preview lists three upcoming dates and a more link without creating messages' do
    post member_session_path, params: { member: { email: @other_member.email, password: 'test-password-123' } }
    assert_no_difference('ChatMessage.count') do
      get new_user_conversation_path(@circle)
    end
    assert_response :success
    assert_select '.inquiry-guidance__message', count: 2
    assert_select '.inquiry-guidance', text: /活動1/
    assert_select '.inquiry-guidance', text: /活動3/
    assert_select '.inquiry-guidance', text: /活動4/, count: 0
    assert_select '.inquiry-guidance', text: /過去の活動/, count: 0
    assert_select '.inquiry-schedule-list a', count: 3
    assert_select '.inquiry-guidance a', text: '他のスケジュールを見る'
    assert_not_includes response.body, '参加確定者だけの集合場所'
    assert_select '[data-inquiry-template-copy]'
  end

  test 'compact schedule labels escape HTML and link to their own details' do
    schedule = @circle.schedules.where('day >= ?', Date.current.to_s).order(:day).first
    schedule.update!(title: '<script>alert(1)</script>')
    post member_session_path, params: { member: { email: @other_member.email, password: 'test-password-123' } }
    get new_user_conversation_path(@circle)
    assert_select '.inquiry-schedule-list script', count: 0
    assert_select '.inquiry-schedule-link[href=?]', "https://circle-book.com/users/#{@circle.id}/schedules/#{schedule.id}", text: /<script>/
  end

  test 'guidance snapshots precede first inquiry only and do not count as an owner reply' do
    conversation = Conversation.for_member!(@circle, @other_member)
    conversation.send_message!('member', '参加希望です。')
    assert_equal %w[system system member], conversation.chat_messages.order(:id).pluck(:sender_role)
    snapshot = conversation.chat_messages.where(sender_role: 'system').pluck(:body)
    assert_nil conversation.accepted_at
    assert_nil conversation.review_deadline
    assert_nil conversation.member_notification_due_at
    assert conversation.owner_notification_due_at
    @circle.update!(template: '変更後の確認事項')
    conversation.send_message!('member', '経験者です。')
    assert_equal snapshot, conversation.chat_messages.where(sender_role: 'system').pluck(:body)
    assert_equal 2, conversation.chat_messages.where(sender_role: 'system').count
    assert_raises(Conversation::NotAllowed) { conversation.send_message!('system', '偽の自動案内') }
  end

  test 'invalid first message rolls back automatic guidance' do
    conversation = Conversation.for_member!(@circle, @other_member)
    assert_raises(ActiveRecord::RecordInvalid) { conversation.send_message!('member', '') }
    assert_empty conversation.reload.chat_messages
  end

  test 'legacy long templates are stored completely without exceeding message size limits' do
    text = '確認事項です。' * 400
    @circle.update_columns(template: text)
    conversation = Conversation.for_member!(@circle, @other_member)
    conversation.send_message!('member', '参加希望です。')
    guidance = conversation.chat_messages.where(sender_role: 'system').order(:id).pluck(:body)
    assert guidance.all? { |body| body.length <= 2000 }
    assert_includes guidance.join, text
  end

  test 'unset settings show the default guidance and three dates link to all schedules' do
    @circle.schedules.delete_all
    @circle.update!(template: '')
    assert_includes CircleInquiryGuidance.new(@circle).messages.join, CircleInquiryGuidance::DEFAULT_TEMPLATE
    3.times { |i| @circle.schedules.create!(title: '練習', venue: '体育館', day: (Date.current + i).to_s) }
    assert_includes CircleInquiryGuidance.new(@circle).messages.join, '他のスケジュールを見る'
  end

  test 'member owner and webmaster all see stored automatic guidance' do
    conversation = Conversation.for_member!(@circle, @other_member)
    conversation.send_message!('member', '参加希望です。')
    post member_session_path, params: { member: { email: @other_member.email, password: 'test-password-123' } }
    get conversation_path(conversation)
    assert_response :success
    assert_select '.inquiry-guidance__message', count: 2
    assert_select '.inquiry-guidance__edit', count: 0
    delete destroy_member_session_path
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    get conversation_path(conversation)
    assert_response :success
    assert_select '.inquiry-guidance__message', count: 2
    assert_select '.inquiry-guidance__edit[href=?]', inquiry_settings_path(@circle), count: 1
    delete destroy_admin_user_session_path
    master = Webmaster.create!(id: 1, email: 'master-guidance@example.test', password: 'test-password-123')
    post webmaster_session_path, params: { webmaster: { email: master.email, password: 'test-password-123' } }
    get super_admin_conversation_path(conversation)
    assert_response :success
    assert_select '.wm-badge', text: '自動案内', count: 2
    assert_includes response.body, '参加希望日'
  end

  test 'default guidance can be quoted edited and preserved as a snapshot' do
    @circle.update!(template: nil)
    post member_session_path, params: { member: { email: @other_member.email, password: 'test-password-123' } }
    get new_user_conversation_path(@circle)
    assert_select '[data-inquiry-template-copy]' do |buttons|
      assert_equal CircleInquiryGuidance::DEFAULT_TEMPLATE, buttons.first['data-inquiry-template-copy']
    end
    conversation = Conversation.for_member!(@circle, @other_member)
    conversation.send_message!('member', '参加希望です。')
    snapshot = conversation.chat_messages.where(sender_role: 'system').pluck(:body)
    assert_includes snapshot.join, CircleInquiryGuidance::DEFAULT_TEMPLATE
    delete destroy_member_session_path
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    get inquiry_settings_path(@circle)
    assert_select 'textarea', text: CircleInquiryGuidance::DEFAULT_TEMPLATE
    patch inquiry_settings_path(@circle), params: { user: { template: '参加希望日を教えてください。' } }
    assert_equal '参加希望日を教えてください。', @circle.reload.template
    assert_includes CircleInquiryGuidance.new(@circle).messages.join, @circle.template
    assert_equal snapshot, conversation.chat_messages.where(sender_role: 'system').pluck(:body)
  end

  test 'only owner can edit guidance and unrelated fields cannot be changed' do
    outsider = AdminUser.create!(email: 'guidance-outsider@example.test', password: 'test-password-123', email_verified_at: Time.current)
    other_circle = @circle.dup
    other_circle.assign_attributes(admin_user: outsider, unique_id: nil)
    other_circle.save!
    post admin_user_session_path, params: { admin_user: { email: outsider.email, password: 'test-password-123' } }
    patch inquiry_settings_path(@circle), params: { user: { template: '他人の更新' } }
    assert_redirected_to circles_path
    refute_equal '他人の更新', @circle.reload.template
    delete destroy_admin_user_session_path
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    get inquiry_settings_path(@circle)
    assert_response :success
    assert_select 'textarea', text: /参加希望日/
    original_name = @circle.name
    patch inquiry_settings_path(@circle), params: { user: { template: '・参加希望日を教えてください', name: '勝手な名前変更' } }
    assert_redirected_to inquiry_settings_path(@circle)
    assert_equal '・参加希望日を教えてください', @circle.reload.template
    assert_equal original_name, @circle.name
  end
end
