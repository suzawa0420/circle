# Only use with the isolated local demonstration database.
raise 'This seed requires the isolated local chat database' unless Rails.env.development? && ActiveRecord::Base.connection_db_config.database == 'circle_chat_development'
load Rails.root.join('db/seeds/chat_catalog.rb')
category = Category.find_by!(kana: 'ball-sports')
event = Event.find_by!(ruby: 'basketball')
prefecture = Prefecture.find_by!(kana: 'tokyo')
owner = AdminUser.find_or_create_by!(email: 'chat-owner@example.test') { |v| v.password = 'Local-demo-2026'; v.nickname = '主催者デモ' }
member = Member.find_or_create_by!(email: 'chat-member@example.test') { |v| v.password = 'Local-demo-2026'; v.nickname = 'さくら'; v.email_verified_at = Time.current; v.profile = '週末にバスケットボールを楽しんでいます。よろしくお願いします。' }
Member.find_or_create_by!(email: 'chat-new-member@example.test') { |v| v.password = 'Local-demo-2026'; v.nickname = '新規参加者デモ'; v.email_verified_at = Time.current }
circle = User.find_or_create_by!(admin_user: owner, name: '週末バスケ・ローカル確認用') do |v|
  v.appeal = '週末に楽しくバスケットボールをしています。初心者の方も歓迎です。' * 6
  v.event = event; v.category = category; v.prefecture = prefecture
  v.area = '東京都'; v.schedule = '土曜日'; v.switch = '募集中'
  v.last_post = Time.current.to_s
end
conversation = Conversation.for_member!(circle, member)
conversation.send_message!('member', 'はじめまして。初心者ですが、参加できますか？') if conversation.chat_messages.empty?
puts "Demo circle: /circles/#{circle.id}"
puts "Demo chat: /conversations/#{conversation.to_param}"
puts "Public profile: /member_profiles/#{member.id}"
