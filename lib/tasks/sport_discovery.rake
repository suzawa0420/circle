namespace :sports do
  desc 'Read-only sport supply and delivered inquiry conversations over the last 28 days'
  task metrics: :environment do
    require 'json'
    puts JSON.generate(%w[sport recruiting updated_within_90_days inquiry_conversations_28_days])
    Event.where(ruby: %w[soft-tennis pickleball ski road-bike mountain swimming]).order(:order).each do |sport|
      population = User.publicly_visible.for_event(sport.id)
      recruiting = population.where(switch: '募集中')
      conversations = Conversation.where(user_id: population.select(:id))
      inquiries = ChatMessage.deliverable.where(conversation_id: conversations.select(:id), sender_role: 'member')
        .where('created_at >= ?', 28.days.ago).distinct.count(:conversation_id)
      puts JSON.generate([sport.ruby, recruiting.count, recruiting.where("user_time ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}' AND user_time >= ?", 90.days.ago.to_date.iso8601).count, inquiries])
    end
  end

  desc 'Read-only classification candidates; never changes circles'
  task audit: :environment do
    require 'json'
    puts JSON.generate(%w[circle_id current_sport candidate status url])
    terms = { 'ソフトテニス' => 'soft-tennis', '軟式テニス' => 'soft-tennis',
              'ピックルボール' => 'pickleball', 'スキー' => 'ski', 'サーフィン' => 'surfing' }
    User.publicly_visible.includes(:event).find_each do |circle|
      text = [circle.name, circle.recruitment, circle.appeal].join(' ')
      terms.select { |word, _| text.include?(word) }.values.uniq.each do |slug|
        next if circle.event.ruby == slug
        puts JSON.generate([circle.id, circle.event.ruby, slug, circle.switch, "https://circle-book.com/circles/#{circle.id}"])
      end
    end
  end
end
