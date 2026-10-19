module SchedulesHelper
  SCHEDULE_WEEKDAYS = %w[日 月 火 水 木 金 土].freeze

  # Never carry request parameters or a member-only URL into a public share.
  def schedule_share_url(schedule)
    "https://circle-book.com#{user_schedule_path(schedule.user_id, schedule.id)}"
  end

  def schedule_share_text(schedule)
    plain = ->(value, length) { CGI.unescapeHTML(strip_tags(value.to_s)).squish.truncate(length) }
    date = Date.iso8601(schedule.day)
    lines = [plain.call(schedule.title.presence || 'イベント', 50), '',
      "#{date.strftime('%Y年%-m月%-d日')}（#{SCHEDULE_WEEKDAYS[date.wday]}）"]
    lines << calendar_schedule_time(schedule) if schedule.time_s || schedule.time_e
    lines << "場所：#{plain.call(schedule.venue, 25)}" if schedule.venue.present?
    lines.concat(['', '詳細・お問い合わせはこちら']).join("\n")
  end

  def schedule_share_intent(destination, text:, url:)
    base = destination == :threads ? 'https://www.threads.com/intent/post' : 'https://twitter.com/intent/tweet'
    "#{base}?#{ { text: text, url: url }.to_query }"
  end

  def event_listing_heading(title)
    period = @relative_day.presence || (@event_date.present? ? @day : nil)
    context = "#{@prefecture&.name || '全国'}の#{@event&.name}"
    subject = "#{EventSearchPage.subject(@event).delete_prefix(@event&.name.to_s)}一覧"
    page = title.delete_prefix("#{period.present? ? "#{period}・" : ''}#{context}#{subject}")

    period_label = @relative_day.present? ? "#{@relative_day}開催予定の" : period
    safe_join([
      content_tag(:span, class: 'event-results__heading-lead') do
        safe_join([
          content_tag(:span, "【全#{number_with_delimiter(@result_count)}件】", class: 'event-results__heading-count'),
          (content_tag(:span, period_label, class: 'event-results__heading-period') if period_label.present?)
        ])
      end,
      content_tag(:span, class: 'event-results__heading-main') do
        safe_join([
          content_tag(:span, context, class: 'event-results__heading-context'),
          content_tag(:span, subject, class: 'event-results__heading-subject'),
          (content_tag(:small, page, class: 'event-results__heading-page') if page.present?)
        ])
      end
    ])
  end

  def event_listing_path(filters = {}, period: nil, date: nil, **keywords)
    filters = filters.merge(keywords)
    EventSearchPage.path(event: filters[:event], prefecture: filters[:pref], period: period, date: date)
  end

  def event_listing_breadcrumbs
    items = [['イベント開催予定', '/dates']]
    if @event
      items << ["#{@event.name}の開催予定", event_listing_path(event: @event.ruby)]
    end
    if @prefecture
      items << ["#{@prefecture.name}の開催予定", event_listing_path(@filter_query)]
    end
    items.uniq { |_, path| path }
  end

  def event_listing_structured_data
    return unless public_structured_data_page? && @schedules.any?
    title = @event_day_title || @event_hub_title
    breadcrumb_data = site_breadcrumb_structured_data
    entries = @schedules.map do |schedule|
      { 'url' => "https://circle-book.com#{user_schedule_path(schedule.user_id, schedule.id)}",
        'name' => schedule.title.presence || "#{schedule.user.event&.name}の活動" }
    end
    list = structured_collection(entries, offset: @schedules.offset_value, name: title)
    {
      '@context' => 'https://schema.org',
      '@graph' => [
        breadcrumb_data&.except('@context'),
        list.except('@context')
      ].compact
    }
  end

  def public_event_structured_data(schedule, user:, accepted_count: 0)
    # Required date/time and a public venue must be supplied by the organizer;
    # never infer them from private venue/address fields or a circle profile.
    return unless public_structured_data_page? && user.publicly_visible? && schedule.time_s && schedule.venue.present?
    return if user.prefecture.name.to_s.include?('オンライン')
    date = Date.iso8601(schedule.day)
    zone = Time.find_zone!('Tokyo')
    start = zone.local(date.year, date.month, date.day, schedule.time_s.hour, schedule.time_s.min)
    image = schedule_image_source(schedule, user: user)
    image = 'https://circle-book.com' + image if image.start_with?('/')
    data = {
      '@context' => 'https://schema.org', '@type' => 'Event',
      '@id' => "https://circle-book.com#{user_schedule_path(user, schedule)}#event",
      name: schedule.title.presence || "#{user.event.name}の活動", startDate: start.iso8601,
      url: "https://circle-book.com#{user_schedule_path(user, schedule)}", image: image,
      eventStatus: "https://schema.org/#{schedule.recruitment == '中止' ? 'EventCancelled' : 'EventScheduled'}",
      eventAttendanceMode: 'https://schema.org/OfflineEventAttendanceMode',
      location: { '@type' => 'Place', name: schedule.venue, address: { '@type' => 'PostalAddress', addressRegion: user.prefecture.name, addressCountry: 'JP' } },
      organizer: { '@type' => 'Organization', '@id' => circle_schema_id(user), name: user.name, url: "https://circle-book.com#{circle_path(user)}" },
      mainEntityOfPage: { '@type' => 'WebPage', '@id' => structured_page_url }
    }
    if schedule.time_e
      ending = zone.local(date.year, date.month, date.day, schedule.time_e.hour, schedule.time_e.min)
      ending += 1.day if ending < start
      data[:endDate] = ending.iso8601
    end
    data[:description] = strip_tags(schedule.note).squish.truncate(500) if schedule.note.present?
    status = public_schedule_status(schedule, accepted_count: accepted_count)
    cost = schedule.cost.to_s.strip
    price = if cost == '無料'
      0
    elsif cost.match?(/\A[¥￥]?\s*(?:\d+|\d{1,3}(?:,\d{3})+)\s*円?\z/)
      cost.delete('¥￥,円 ').to_i
    end
    if price && !%w[cancelled ended].include?(status[:key])
      data[:offers] = { '@type' => 'Offer', url: data[:url], price: price, priceCurrency: 'JPY',
        availability: "https://schema.org/#{status[:key] == 'full' ? 'SoldOut' : 'InStock'}" }
    end
    data
  rescue Date::Error
    nil
  end

  def public_schedule_page_structured_data(schedule, user:)
    return unless public_structured_data_page? && user.publicly_visible?
    { '@context' => 'https://schema.org', '@type' => 'WebPage', '@id' => structured_page_url,
      'url' => structured_page_url, 'name' => schedule.title.presence || "#{user.event.name}の活動",
      'about' => { '@type' => 'Organization', '@id' => circle_schema_id(user), 'name' => user.name.to_s } }
  end

  def schedule_image_source(schedule, user: schedule.user)
    return schedule.top_image.url if schedule.top_image.present?
    return user.pic_header.url if user.pic_header.present?

    event = user.event
    [["events", event&.ruby], ["categories", event&.category&.kana]].each do |directory, slug|
      next unless slug.to_s.match?(/\A[a-z0-9_-]+\z/)
      path = "/images/#{directory}/#{slug}.jpg"
      return path if File.file?(Rails.root.join('public', path.delete_prefix('/')))
    end
    '/images/events/event.jpg'
  end

  def public_schedule_status(schedule, accepted_count:, now: Time.current)
    now = now.in_time_zone('Tokyo')
    return { key: 'cancelled', label: '中止' } if schedule.recruitment == '中止'
    start_clock = schedule.time_s&.strftime('%H:%M:%S')
    end_clock = schedule.time_e&.strftime('%H:%M:%S')
    ended_today = schedule.day == now.to_date.iso8601 && end_clock &&
      (!start_clock || end_clock >= start_clock) && end_clock <= now.strftime('%H:%M:%S')
    return { key: 'ended', label: '開催終了' } if schedule.day < now.to_date.iso8601 || ended_today
    remaining = schedule.recruitment_numbers.to_i - accepted_count
    limited = schedule.recruitment_numbers.to_i.positive?
    return { key: 'full', label: '満員' } if schedule.recruitment == '募集終了' || (limited && remaining <= 0)
    return { key: 'few', label: '残りわずか' } if limited && remaining <= 3
    { key: 'open', label: '募集中' }
  end

  def calendar_schedule_status(schedule, calendar)
    return { key: 'cancelled', mark: '×', label: '中止' } if schedule.recruitment == '中止'
    return { key: 'ended', mark: '済', label: '開催終了' } if schedule.day < calendar.today.iso8601
    remaining = schedule.recruitment_numbers.to_i - calendar.accepted_count(schedule)
    limited = schedule.recruitment_numbers.to_i.positive?
    if schedule.recruitment == '募集終了' || (limited && remaining <= 0)
      { key: 'full', mark: '満', label: '満員' }
    elsif limited && remaining <= 3
      { key: 'few', mark: '△', label: '残りわずか' }
    else
      { key: 'open', mark: '○', label: '募集中' }
    end
  end

  def calendar_schedule_time(schedule)
    return '時間未定' unless schedule.time_s || schedule.time_e
    [schedule.time_s&.strftime('%H:%M') || '未定', schedule.time_e&.strftime('%H:%M') || '未定'].join('–')
  end

  def calendar_schedule_date(date)
    "#{date.month}月#{date.day}日（#{SCHEDULE_WEEKDAYS[date.wday]}）"
  end
end
