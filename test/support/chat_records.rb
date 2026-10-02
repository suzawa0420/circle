module ChatRecords
  def create_chat_records
    category = Category.create!(name: '球技', kana: 'chat-ball', order: '1')
    event = Event.create!(name: 'バスケ', ruby: 'chat-basketball', category: category, order: '1')
    prefecture = Prefecture.create!(name: '東京都', kana: 'chat-tokyo', order: '1', sort: 1)
    @owner = AdminUser.create!(email: 'chat-owner@example.test', password: 'test-password-123', email_verified_at: Time.current)
    @circle = User.create!(name: 'チャット検証サークル', appeal: '地域で定期的に練習しています。初心者も経験者も歓迎します。' * 6,
                          event: event, prefecture: prefecture, category: category, admin_user: @owner,
                          area: '世田谷区', schedule: '毎週土曜', switch: '募集中')
    @member = Member.create!(email: 'chat-member@example.test', nickname: '参加者さくら', password: 'test-password-123', email_verified_at: Time.current)
    @other_member = Member.create!(email: 'chat-other@example.test', nickname: '別の参加者', password: 'test-password-123', email_verified_at: Time.current)
    @conversation = Conversation.for_member!(@circle, @member)
    @conversation.send_message!('member', 'はじめまして。参加できますか？')
  end

  def accept_conversation
    @conversation.send_message!('owner', 'お問い合わせありがとうございます。ぜひお越しください。')
  end

  def member_evaluation
    { score: 1, comment: '温かく迎えていただき、楽しく参加できました。', participated: true }
  end

  def owner_evaluation
    { score: 0, comment: '途中から連絡が取れなくなってしまいました。' }
  end
end
