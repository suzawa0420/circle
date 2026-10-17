# Only public, same-circle destinations are resolved; no referrer or arbitrary URL is stored.
class CircleInquiryContext
  PURPOSE = 'circle-inquiry-context'.freeze
  LABELS = { 'details' => 'サークル詳細', 'schedules' => '活動日一覧', 'schedule' => '活動日',
             'reviews' => '口コミ', 'questions' => 'Q&A', 'question' => 'Q&A',
             'blogs' => 'ブログ一覧', 'blog' => 'ブログ' }.freeze

  def self.issue(user, kind:, record_id: nil)
    return unless build(user, kind, record_id)
    Rails.application.message_verifier(PURPOSE).generate({ 'user_id' => user.id, 'kind' => kind, 'record_id' => record_id }, purpose: PURPOSE)
  end

  def self.resolve(user, token)
    return unless token.is_a?(String) && token.bytesize <= 2048
    data = Rails.application.message_verifier(PURPOSE).verified(token, purpose: PURPOSE)
    return unless data.is_a?(Hash) && data['user_id'] == user.id
    build(user, data['kind'], data['record_id'])
  end

  def self.build(user, kind, record_id)
    return unless LABELS.key?(kind) && user.publicly_visible?
    routes = Rails.application.routes.url_helpers
    title = user.name
    timing = nil
    path = case kind
           when 'details' then routes.circle_path(user)
           when 'schedules' then routes.user_schedules_path(user)
           when 'reviews' then routes.user_reviews_path(user)
           when 'questions' then routes.user_questions_path(user)
           when 'blogs' then routes.circle_blogs_path(user)
           when 'schedule'
             record = user.schedules.find_by(id: record_id)
             return unless record
             title = record.title.presence || '活動予定'
             date = Date.iso8601(record.day)
             timing = "#{date.strftime('%Y年%-m月%-d日')}（#{%w[日 月 火 水 木 金 土][date.wday]}）"
             timing += " #{record.time_s.strftime('%H:%M')}〜#{record.time_e&.strftime('%H:%M') || '未定'}" if record.time_s
             routes.user_schedule_path(user, record)
           when 'blog'
             record = user.blogs.publicly_visible.find_by(id: record_id)
             return unless record
             title = record.title
             routes.circle_blog_path(user, record)
           when 'question'
             record = user.questions.find_by(id: record_id)
             return unless record
             title = record.content
             routes.user_question_path(user, record)
           end
    { 'kind' => kind, 'label' => LABELS.fetch(kind), 'title' => title.to_s.truncate(300), 'path' => path, 'timing' => timing }.compact
  rescue Date::Error
    nil
  end
end
