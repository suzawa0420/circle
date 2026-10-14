module SchedulesHelper
  SCHEDULE_WEEKDAYS = %w[日 月 火 水 木 金 土].freeze

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
    title = @event_day_title || @event_hub_title
    path = @event_day_path || @event_hub_path
    query = params[:page].to_i > 1 ? "?page=#{params[:page].to_i}" : ''
    breadcrumbs = event_listing_breadcrumbs
    breadcrumbs += [[title, path + query]] unless breadcrumbs.last&.last == path + query
    {
      '@context' => 'https://schema.org',
      '@graph' => [
        { '@type' => 'BreadcrumbList', itemListElement: breadcrumbs.each_with_index.map { |(name, url), i| { '@type' => 'ListItem', position: i + 1, name: name, item: 'https://circle-book.com' + url } } },
        { '@type' => 'ItemList', name: title, url: 'https://circle-book.com' + path + query,
          itemListElement: @schedules.each_with_index.map { |schedule, i| { '@type' => 'ListItem', position: @schedules.offset_value + i + 1, url: "https://circle-book.com#{user_schedule_path(schedule.user_id, schedule.id)}", name: schedule.title.presence || "#{schedule.user.event&.name}の活動" } } }
      ]
    }
  end

  def public_event_structured_data(schedule, user:)
    # Required date/time and a public venue must be supplied by the organizer;
    # never infer them from private venue/address fields or a circle profile.
    return unless schedule.time_s && schedule.venue.present?
    date = Date.iso8601(schedule.day)
    zone = Time.find_zone!('Tokyo')
    start = zone.local(date.year, date.month, date.day, schedule.time_s.hour, schedule.time_s.min)
    image = schedule_image_source(schedule, user: user)
    image = 'https://circle-book.com' + image if image.start_with?('/')
    data = {
      '@context' => 'https://schema.org', '@type' => 'Event',
      name: schedule.title.presence || "#{user.event.name}の活動", startDate: start.iso8601,
      url: "https://circle-book.com#{user_schedule_path(user, schedule)}", image: image,
      eventStatus: "https://schema.org/#{schedule.recruitment == '中止' ? 'EventCancelled' : 'EventScheduled'}",
      eventAttendanceMode: 'https://schema.org/OfflineEventAttendanceMode',
      location: { '@type' => 'Place', name: schedule.venue, address: { '@type' => 'PostalAddress', addressRegion: user.prefecture.name, addressCountry: 'JP' } },
      organizer: { '@type' => 'Organization', name: user.name, url: "https://circle-book.com#{circle_path(user)}" }
    }
    if schedule.time_e
      ending = zone.local(date.year, date.month, date.day, schedule.time_e.hour, schedule.time_e.min)
      ending += 1.day if ending < start
      data[:endDate] = ending.iso8601
    end
    data[:description] = strip_tags(schedule.note).squish.truncate(500) if schedule.note.present?
    data
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
