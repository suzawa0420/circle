require 'test_helper'
require_relative '../support/chat_records'

class ChatSpamDetectorTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  include ChatRecords
  setup { create_chat_records }

  test 'adult advertisements are held with inspectable independent reasons' do
    result = ChatSpamDetector.evaluate(@conversation, "性愛預約服務 LINE ID: bad Telegram: @bad https://t.me/bad #宣傳 #台北 #台中 #服務 #廣告 #預約")
    assert result.held?
    assert_equal 9, result.score
    assert_equal %w[adult sales contacts hashtags], result.reasons
  end

  test 'normal inquiry foreign language LINE and a single QR link are allowed' do
    ['こんにちは。料金を教えてください。LINE交換できますか？', 'Hello, can I join your circle?', '您好，請問可以參加活動嗎？', 'LINE ID: sample https://example.test/qr', '予約の場所 https://example.test/map https://example.test/schedule'].each do |body|
      assert_not ChatSpamDetector.evaluate(@conversation, body).held?, body
    end
  end

  test 'specific confirmed destinations are matched without banning an entire shared platform' do
    ChatSpamDestination.create!(destination: 't.me/bad')
    assert ChatSpamDetector.evaluate(@conversation, 'https://t.me/bad?ref=other').held?
    assert_not ChatSpamDetector.evaluate(@conversation, 'https://t.me/friendly').held?
    assert_not ChatSpamDetector.evaluate(@conversation, 'https://t.me/bad-other').held?
  end

  test 'normalization detects meaningful near copies but not short greetings' do
    assert_equal ChatSpamDetector.normalized(' ＬＩＮＥ ID：ＡＢＣ '), ChatSpamDetector.normalized('line id abc')
    assert_not ChatSpamDetector.similar?('こんにちは', 'こんにちは')
    text = ChatSpamDetector.normalized('この地域で活動しています。新しいサービスのご案内です。ぜひこちらをご覧ください。' * 3)
    assert ChatSpamDetector.similar?(text, text + '案内')
    circles = 2.times.map { @circle.dup.tap { |c| c.name = "別サークル#{SecureRandom.hex(3)}"; c.save! } }
    body = '宣伝のご案内です。こちらから詳細をご確認いただけます。地域ごとにサービスを紹介しています。' * 2 + ' https://example.test/a https://example.test/b'
    circles.each { |c| Conversation.for_member!(c, @member).send_message!('member', body) }
    result = ChatSpamDetector.evaluate(@conversation, body)
    assert result.held?
    assert_includes result.reasons, 'repeated'
    assert_equal 6, result.score
    assert_not ChatSpamDetector.evaluate(@conversation, 'こんにちは').held?
  end

  test 'accepted conversations keep ordinary exchanges outside content scoring' do
    accept_conversation
    message = @conversation.send_message!('member', '性愛預約服務 LINE ID: example Telegram: @example')
    assert message.delivered?
    assert_equal 0, message.spam_score
  end
end
