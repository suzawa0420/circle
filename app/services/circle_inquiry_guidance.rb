# 問い合わせ前のプレビューと、初回送信時に保存する自動案内の共通生成元。
class CircleInquiryGuidance
  def initialize(circle)
    @circle = circle
  end

  def messages
    bodies = []
    schedules = @circle.schedules.where('day >= ?', Date.current.to_s).order(:day, :time_s, :id).limit(4).to_a
    if schedules.any?
      lines = ['活動予定のご案内', '問い合わせの前に、登録済みの活動予定をご確認ください。']
      schedules.first(3).each do |schedule|
        day = Date.parse(schedule.day)
        lines << "\n#{day.strftime('%-m月%-d日')}（#{%w[日 月 火 水 木 金 土][day.wday]}） #{schedule.title}"
        times = [schedule.time_s, schedule.time_e].compact.map { |time| time.strftime('%H:%M') }
        lines << times.join('〜') if times.any?
        lines << schedule.venue.to_s
        lines << schedule.recruitment if schedule.recruitment.present?
        lines << routes.user_schedule_url(@circle, schedule, host: 'circle-book.com', protocol: 'https')
      end
      if schedules.length > 3
        lines << "\nほかの活動予定も見る"
        lines << routes.user_schedules_url(@circle, host: 'circle-book.com', protocol: 'https')
      end
      bodies << lines.join("\n")
    end
    if @circle.template.present?
      bodies << "主催者からのご案内・確認事項\n#{@circle.template}"
    end
    # 既存の長いテンプレートも省略せず、通常メッセージの上限内で保存する。
    bodies.flat_map { |body| body.scan(/.{1,2000}/m) }
  end

  private

  def routes
    Rails.application.routes.url_helpers
  end
end
