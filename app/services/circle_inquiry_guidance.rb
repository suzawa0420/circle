# 問い合わせ前のプレビューと、初回送信時に保存する自動案内の共通生成元。
class CircleInquiryGuidance
  DEFAULT_TEMPLATE = <<~TEXT.strip.freeze
    以下の内容をコピーして、ご回答ください。

    名前： 例）鈴木
    性別： 例）男
    年代： 例）30代
    経歴： 例）初心者

    ▼メッセージ
    例）初心者ですがよろしくお願いします！
  TEXT

  DEFAULT_ANSWER = "名前：\n性別：\n年代：\n経歴：\n\n▼メッセージ\n".freeze

  def self.template_for(circle)
    circle.template.presence || DEFAULT_TEMPLATE
  end

  def self.default_answer_for(circle)
    # The existing free-text setting may contain organizer announcements, not just questions.
    DEFAULT_ANSWER if without_whitespace(template_for(circle)) == without_whitespace(DEFAULT_TEMPLATE)
  end

  def self.unchanged_default_answer?(circle, answer)
    default = default_answer_for(circle)
    default && without_whitespace(answer) == without_whitespace(default)
  end

  def self.without_whitespace(text)
    text.to_s.gsub(/[[:space:]]/, '')
  end
  private_class_method :without_whitespace

  def initialize(circle)
    @circle = circle
  end

  def messages
    bodies = []
    schedules = @circle.schedules.where('day >= ?', Date.current.to_s).order(:day, :time_s, :id).limit(4).to_a
    if schedules.any?
      lines = ['直近の活動日は以下です。']
      schedules.first(3).each do |schedule|
        day = Date.parse(schedule.day)
        times = [schedule.time_s, schedule.time_e].compact.map { |time| time.strftime('%H:%M') }
        lines << ["#{day.strftime('%-m月%-d日')}（#{%w[日 月 火 水 木 金 土][day.wday]}）", times.join('〜'), schedule.venue, schedule.title].compact.join(' ')
        lines << routes.user_schedule_url(@circle, schedule, host: 'circle-book.com', protocol: 'https')
      end
      lines << '他のスケジュールを見る'
      lines << routes.user_schedules_url(@circle, host: 'circle-book.com', protocol: 'https')
      bodies << lines.join("\n")
    end
    bodies << "主催者からのご案内・確認事項\n#{self.class.template_for(@circle)}"
    # 既存の長いテンプレートも省略せず、通常メッセージの上限内で保存する。
    bodies.flat_map { |body| body.scan(/.{1,2000}/m) }
  end

  private

  def routes
    Rails.application.routes.url_helpers
  end
end
