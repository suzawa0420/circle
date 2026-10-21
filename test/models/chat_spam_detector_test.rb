require 'test_helper'
require_relative '../support/chat_records'

class ChatSpamDetectorTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  include ChatRecords
  setup { create_chat_records }

  test 'blocked promotion cannot be sent by either role before or after acceptance' do
    2.times do
      %w[member owner].each do |role|
        ['日本椿兔', 'Googleで「日本椿兔」と検索してください。',
         '日 本・椿 兔', "日本椿\u200b兔", '日本椿&#20820;', '日本<b>椿</b>兔'].each do |body|
          assert_no_difference ['ChatMessage.count', 'ActionMailer::Base.deliveries.size'] do
            error = assert_raises(ActiveRecord::RecordInvalid) { @conversation.send_message!(role, body) }
            assert error.record.errors.of_kind?(:body, :invalid), body
          end
        end
      end
      accept_conversation unless @conversation.accepted_at
    end
    assert @conversation.send_message!('member', '日本の椿を観察する会に参加したいです。').delivered?
  end

  test 'both roles cannot insert the blocked term by editing and legacy messages stay deletable' do
    accept_conversation
    %w[member owner].each do |role|
      message = @conversation.send_message!(role, '参加日を確認します。')
      assert_raises(ActiveRecord::RecordInvalid) { message.revise!(role, body: '日本椿兔') }
      assert_equal '参加日を確認します。', message.reload.body
      message.update_column(:body, '以前の日本椿兔の投稿')
      assert message.revise!(role, delete: true)
      assert message.reload.deleted_at
    end
  end

  test 'participant and organizer profiles and automatic reply templates reject the blocked term' do
    [@member, @owner].each do |actor|
      %i[nickname profile].each do |field|
        actor.assign_attributes(field => '日本椿兔です。')
        refute actor.valid?, "#{actor.class} #{field}"
        assert actor.errors.of_kind?(field, :invalid)
        actor.reload
      end
      actor.update_column(:profile, '以前の日本椿兔の紹介です。')
      assert actor.update(nickname: '通常の名前')
    end
    (CircleProfilePolicy::FIELDS + [:template]).each do |field|
      circle = @circle.dup
      circle.public_send("#{field}=", '日本椿兔のご案内です。')
      refute circle.valid?, field
      assert circle.errors.of_kind?(field, :invalid), field
    end
  end

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

  test 'editorial and commercial offers are held before delivery even without a link' do
    [
      'サイト内にはサークルの参加者募集を掲載できるページがあります。サークルを始めたきっかけや普段の撮影のことを、短い記事で紹介できたらと思い、ご連絡しました。まずはオンラインで少しお話しできませんか？',
      '活動について取材させていただけませんか？',
      'インタビューのお願いです。オンラインでお話を伺いたいです。',
      '弊社の集客サービスをご紹介したく、ご連絡しました。',
      '当サイトに掲載しませんか？ https://example.test/'
    ].each do |body|
      result = ChatSpamDetector.evaluate(@conversation, body)
      assert result.held?, body
      assert_includes result.reasons, 'solicitation'
    end

    message = @conversation.send_message!('member', '活動について取材させていただけませんか？')
    assert_equal 'held', message.moderation_status
    assert_not @conversation.chat_messages.visible_to('owner').exists?(message.id)
  end

  test 'sales and financial pitches require a topic and an offer' do
    {
      'business_offer' => [
        '集客支援のご提案でご連絡しました。',
        'ホームページ制作のサービスを導入しませんか？',
        'ＳＥＯ対策をご紹介させていただきます。',
        '広告運用をお手伝いさせていただけませんか。'
      ],
      'financial_pitch' => [
        '副収入に関する説明会へご招待します。',
        '不労所得を得て稼げる仕組みをご紹介します。',
        '資産運用セミナーに参加しませんか？',
        '副業で収入を増やしませんか？',
        'セミナーで資産運用についてご案内します。'
      ],
      'solicitation' => [
        '取材のご相談でご連絡しました。',
        '当サイトへの掲載のご相談です。',
        'メディアを運営しており、活動についてお話を伺いたいです。'
      ]
    }.each do |reason, bodies|
      bodies.each do |body|
        result = ChatSpamDetector.evaluate(@conversation, body)
        assert result.held?, body
        assert_includes result.reasons, reason
      end
    end
  end

  test 'ordinary participant questions and occupations do not trigger pitch reasons' do
    [
      'ホームページ制作の仕事をしています。土曜日に参加できますか？',
      '副業があるので平日夜に参加したいです。',
      '資産運用を勉強しています。趣味の写真仲間を探しています。',
      'LINEで連絡できますか？料金を教えてください。',
      'サークルのオープンチャットへ参加したいです。',
      '営業や投資の勧誘は禁止ですか？',
      'SEO対策について書かれた記事を読みました。参加希望です。',
      'LINEに追加しました。参加日はいつですか？'
    ].each do |body|
      result = ChatSpamDetector.evaluate(@conversation, body)
      assert_not result.held?, body
      assert_empty result.reasons & %w[solicitation business_offer financial_pitch external_invitation], body
    end
  end

  test 'ambiguous external invitation combines with contacts or repeated destinations' do
    invitation = '詳しくはこちら。LINEに登録してください。'
    result = ChatSpamDetector.evaluate(@conversation, invitation + ' https://example.test/info')
    assert_equal 3, result.score
    assert_not result.held?
    assert_equal ['external_invitation'], result.reasons

    result = ChatSpamDetector.evaluate(@conversation, invitation + ' https://example.test/info https://example.test/join')
    assert result.held?
    assert_equal 5, result.score

    bodies = [
      '写真の活動について連絡しました。https://example.test/info',
      '週末にお時間はありますでしょうか。https://example.test/info'
    ]
    send_to_other_circles(bodies)
    result = ChatSpamDetector.evaluate(@conversation, invitation + ' https://example.test/info?ref=third')
    assert result.held?
    assert_equal 5, result.score
    assert_equal %w[external_invitation shared_destination], result.reasons
    assert_not ChatSpamDetector.evaluate(@conversation, invitation + ' https://example.test/different').held?
    assert_not ChatSpamDetector.evaluate(@conversation, 'https://example.test/info').held?

    travel 31.minutes do
      assert_not ChatSpamDetector.evaluate(@conversation, invitation + ' https://example.test/info').held?
    end
    assert_not ChatSpamDetector.evaluate(Conversation.for_member!(@circle, @other_member), invitation + ' https://example.test/info').held?
  end

  test 'multiple posts in one circle do not count as multiple destinations' do
    circle = @circle.dup.tap { |c| c.name = '別の問い合わせ先'; c.save! }
    conversation = Conversation.for_member!(circle, @member)
    2.times { conversation.send_message!('member', 'https://example.test/info') }
    result = ChatSpamDetector.evaluate(@conversation, '詳しくはこちら。LINEに登録してください。https://example.test/info')
    assert_not result.held?
    assert_not_includes result.reasons, 'shared_destination'
  end

  test 'different links sent to different circles are not one repeated destination' do
    send_to_other_circles(['https://example.test/a', 'https://example.test/b'])
    result = ChatSpamDetector.evaluate(@conversation, 'https://example.test/a https://example.test/b')
    assert_equal ['contacts'], result.reasons
    assert_not result.held?
  end

  test 'campaign copies with different addressee lines combine with external invitation' do
    body = '詳しくはこちら。LINEに登録してください。活動する場所や時間などの情報をまとめていますので、ご興味がありましたら一度ご確認をお願いいたします。'
    send_to_other_circles(["東京フォトウォークご担当者様\n#{body}", "大阪の写真サークルの皆さま\n#{body}"])
    result = ChatSpamDetector.evaluate(@conversation, "横浜カメラ仲間様\n#{body}")
    assert result.held?
    assert_equal %w[external_invitation repeated], result.reasons
    assert_equal 7, result.score
  end

  test 'participant occupations interests identities and links alone are allowed' do
    [
      '取材の仕事をしています。撮影会に参加したいです。',
      'サイトの記事でこちらを知りました。参加できますか？',
      'LGBTQ+のコミュニティに参加したいです。',
      '写真を紹介したいです。初心者でも参加できますか？',
      '営業職の30代です。趣味で写真を撮っています。',
      '自分のサイトです。https://example.test/ 参加を希望します。'
    ].each do |body|
      assert_not ChatSpamDetector.evaluate(@conversation, body).held?, body
    end
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
    assert_equal 8, result.score
    assert_not ChatSpamDetector.evaluate(@conversation, 'こんにちは').held?
  end

  test 'accepted conversations keep ordinary exchanges outside content scoring' do
    accept_conversation
    message = @conversation.send_message!('member', '性愛預約服務 LINE ID: example Telegram: @example')
    assert message.delivered?
    assert_equal 0, message.spam_score
  end

  private

  def send_to_other_circles(bodies)
    bodies.each do |body|
      circle = @circle.dup.tap { |c| c.name = "別サークル#{SecureRandom.hex(3)}"; c.save! }
      Conversation.for_member!(circle, @member).send_message!('member', body)
    end
  end
end
