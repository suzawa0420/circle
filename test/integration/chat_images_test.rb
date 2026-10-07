require 'test_helper'
require_relative '../support/chat_records'

class ChatImagesTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    @photo = Tempfile.new(['chat-test', '.png'])
    MiniMagick::Tool.new('convert') { |c| c.size '120x120'; c.xc 'white'; c.fill 'black'; c.draw 'rectangle 20,20 60,60'; c << @photo.path }
    @stored_images = []
  end

  teardown do
    @stored_images.each { |image| image.remove! }
    @photo.close!
  end

  test 'one photo can be sent without text, appears in polling and inbox, and only authorized viewers can fetch it' do
    login(@member)
    post message_conversation_path(@conversation), params: { message: { image: upload } }
    assert_response :redirect
    message = @conversation.chat_messages.order(:id).last
    @stored_images << message.image
    assert message.image?
    assert_equal '', message.body
    assert_not message.image.read.start_with?("\xFF\xD8".b), 'storage must contain encrypted bytes'
    assert_not message.image.file.path.start_with?(Rails.public_path.to_s)
    get conversations_path
    assert_select '.chat-talk__preview', text: 'あなた：写真'
    get conversation_path(@conversation)
    assert_select 'input[type=file][name="message[image]"]:not([multiple])', count: 1
    assert_select '.chat-image-link img', count: 1
    get messages_conversation_path(@conversation), as: :json
    assert_includes response.parsed_body['html'], 'chat-image-link'
    path = chat_image_path(@conversation.public_id, message.id)
    before = @conversation.reload.attributes
    get path
    assert_response :success
    assert_equal 'image/jpeg', response.media_type
    assert response.body.b.start_with?("\xFF\xD8".b)
    assert_includes response.headers['Cache-Control'], 'no-store'
    assert_equal before, @conversation.reload.attributes
    assert MiniMagick::Image.read(response.body).valid?

    delete destroy_member_session_path
    get path
    assert_response :unauthorized
    login(@other_member)
    assert_raises(ActiveRecord::RecordNotFound) { get path }
    delete destroy_member_session_path
    login(@owner)
    get path
    assert_response :success
    delete destroy_admin_user_session_path
    master = Webmaster.create!(id: 1, email: 'photo-master@example.test', password: 'test-password-123')
    post webmaster_session_path, params: { webmaster: { email: master.email, password: 'test-password-123' } }
    get path
    assert_response :success
    assert_equal before, @conversation.reload.attributes
    get super_admin_conversation_path(@conversation)
    assert_select '.chat-image-link img', count: 1
  end

  test 'owner photo replies use normal acceptance and read receipts, with text optional' do
    login(@owner)
    post message_conversation_path(@conversation), params: { message: { image: upload, body: '集合場所の写真です。' } }
    assert_response :redirect
    message = @conversation.chat_messages.order(:id).last
    @stored_images << message.image
    assert message.image?
    assert @conversation.reload.accepted_at
    assert @conversation.member_notification_due_at
    assert_equal 'owner', message.sender_role
    assert_equal '集合場所の写真です。', message.body
    delete destroy_admin_user_session_path
    login(@member)
    get conversation_path(@conversation)
    assert @conversation.reload.message_read?(message)
    assert_nil @conversation.member_notification_due_at
  end

  test 'multiple files, forged images, empty submissions and oversized photos create no messages' do
    login(@member)
    assert_no_difference('ChatMessage.count') do
      post message_conversation_path(@conversation), params: { message: { body: '複数画像', image: [upload, upload] } }
    end
    assert_response :redirect
    assert_includes flash[:alert], '1枚'
    @photo.rewind
    @photo.truncate(0)
    @photo.write('<script>not an image</script>')
    @photo.flush
    assert_no_difference('ChatMessage.count') do
      post message_conversation_path(@conversation), params: { message: { image: upload, body: '入力を保持します' } }
    end
    assert_response :unprocessable_entity
    assert_select 'textarea', text: '入力を保持します'
    assert_select '[role=alert]', text: /選び直してください/
    assert_no_difference('ChatMessage.count') { post message_conversation_path(@conversation), params: { message: { body: '' } } }
    assert_response :unprocessable_entity
    @photo.truncate(10.megabytes + 1)
    assert_no_difference('ChatMessage.count') { post message_conversation_path(@conversation), params: { message: { image: upload } } }
    assert_response :unprocessable_entity
  end

  test 'image endpoint scopes message to conversation and does not mark unseen messages read' do
    image_message = @conversation.send_message!('member', '', image: upload)
    @stored_images << image_message.image
    another = Conversation.for_member!(@circle, @other_member)
    another.send_message!('member', '別の会話です。')
    login(@owner)
    assert_raises(ActiveRecord::RecordNotFound) { get chat_image_path(another.public_id, image_message.id) }
    get chat_image_path(@conversation.public_id, image_message.id)
    assert_response :success
    assert_equal 0, @conversation.reload.owner_read_message_id
    @conversation.update!(owner_blocked: true)
    assert_no_difference('ChatMessage.count') { post message_conversation_path(@conversation), params: { message: { image: upload } } }
    assert_response :redirect
  end

  private

  def upload
    Rack::Test::UploadedFile.new(@photo.path, 'image/png')
  end

  def login(account)
    scope = account.is_a?(Member) ? :member : :admin_user
    post public_send("#{scope}_session_path"), params: { scope => { email: account.email, password: 'test-password-123' } }
    assert_response :redirect
  end
end
