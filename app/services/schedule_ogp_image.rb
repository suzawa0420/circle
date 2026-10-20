# frozen_string_literal: true

require 'cgi'
require 'digest'
require 'json'
require 'open3'
require 'tmpdir'

# A deterministic image, built exclusively from the public event information.
class ScheduleOgpImage
  VERSION = '2'
  WIDTH = 1200
  HEIGHT = 630
  WEEKDAYS = %w[日 月 火 水 木 金 土].freeze

  def self.version_for(schedule)
    circle = schedule.user
    Digest::SHA256.hexdigest([VERSION, schedule.cache_key_with_version,
      circle.cache_key_with_version, circle.event&.ruby, circle.event&.category&.kana].to_json).first(24)
  end

  def initialize(schedule)
    @schedule = schedule
  end

  def png
    cache = ActiveSupport::Cache::FileStore.new(Rails.root.join('tmp/cache/schedule-ogp'))
    cache.fetch(self.class.version_for(@schedule), expires_in: 1.day, race_condition_ttl: 10) { render }
  end

  def title_lines
    wrap(@schedule.title.presence || 'イベント', size: 42, width: 552, lines: 3)
  end

  def venue_line
    wrap(@schedule.venue, size: 32, width: 496, lines: 1).first.to_s
  end

  def date_label
    date = Date.iso8601(@schedule.day)
    "#{date.strftime('%Y年%-m月%-d日')}（#{WEEKDAYS[date.wday]}）"
  rescue Date::Error
    '日程未定'
  end

  def time_label
    start = @schedule.time_s&.strftime('%H:%M')
    ending = @schedule.time_e&.strftime('%H:%M')
    return '時間未定' unless start || ending

    [start, ending].join('〜')
  end

  private

  # Conservative glyph widths keep both Japanese and unbroken Latin text
  # inside their columns. Work on graphemes so combining marks stay together.
  def wrap(value, size:, width:, lines:)
    text = CGI.unescapeHTML(ActionView::Base.full_sanitizer.sanitize(value.to_s)).squish
    characters = text.scan(/\X/).first(1000)
    result = []
    lines.times do |line_index|
      line = +''
      used = 0
      while characters.any?
        char_width = characters.first.match?(/\A[\x20-\x7e]\z/) && !characters.first.match?(/[MW@]/) ? 0.7 : 1.0
        break if used + char_width > width.to_f / size
        line << characters.shift
        used += char_width
      end
      if line_index == lines - 1 && characters.any?
        line = line.scan(/\X/)[0...-1].join.rstrip + '…'
      end
      result << line.strip
      break if characters.empty?
    end
    result
  end

  def render
    Dir.mktmpdir('schedule-ogp-') do |directory|
      photo_path = File.join(directory, 'photo.png')
      photo = square_photo
      photo.write(photo_path)
      photo.destroy!

      svg_path = File.join(directory, 'layout.svg')
      layout_path = File.join(directory, 'layout.png')
      output_path = File.join(directory, 'ogp.png')
      File.write(svg_path, layout_svg)
      # Librsvg/fontconfig supplies fallback fonts for Japanese and Latin text.
      # Text is XML-escaped; no user data becomes a file path or command.
      _output, _error, status = Open3.capture3('rsvg-convert', '--output', layout_path, svg_path)
      raise MiniMagick::Error, 'OGP SVG rendering failed' unless status.success?

      MiniMagick::Tool::Convert.new do |command|
        command.background 'white'
        command << layout_path
        command << photo_path
        command.geometry '+48+75'
        command.composite
        command.strip
        command << output_path
      end
      File.binread(output_path)
    end
  end

  def square_photo
    image = uploaded_photo || MiniMagick::Image.open(fallback_photo)
    image.combine_options do |command|
      command.auto_orient
      command.resize '480x480^'
      command.gravity 'center'
      command.extent '480x480'
    end
    image.format 'png'
    image
  end

  def uploaded_photo
    upload = [@schedule.top_image, @schedule.user.pic_header].find(&:present?)
    return unless upload

    # Read through the configured uploader storage; never fetch a supplied URL.
    MiniMagick::Image.read(upload.file.read)
  rescue StandardError => error
    Rails.logger.warn("Schedule OGP photo fallback: #{error.class.name}")
    nil
  end

  def fallback_photo
    event = @schedule.user.event
    [['events', event&.ruby], ['categories', event&.category&.kana], ['events', 'event']].each do |directory, slug|
      next unless slug.to_s.match?(/\A[a-z0-9_-]+\z/)
      path = Rails.root.join('public/images', directory, "#{slug}.jpg")
      return path.to_s if File.file?(path)
    end
  end

  def svg_text(value, x:, y:, size:, color: '#242c29', weight: 'normal', anchor: 'start')
    %(<text x="#{x}" y="#{y}" font-size="#{size}" font-weight="#{weight}" fill="#{color}" text-anchor="#{anchor}">#{CGI.escapeHTML(value)}</text>)
  end

  def icon(name, y:)
    geometry = LucideHelper::ICONS.fetch(name)
    %(<g transform="translate(576 #{y}) scale(1.5)" fill="none" stroke="#58625d" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">#{geometry}</g>)
  end

  def layout_svg
    title = title_lines.each_with_index.map do |line, index|
      svg_text(line, x: 576, y: 116 + index * 59, size: 42, weight: 'bold')
    end.join
    <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg" xml:lang="ja" font-family="sans-serif" width="#{WIDTH}" height="#{HEIGHT}" viewBox="0 0 #{WIDTH} #{HEIGHT}">
        <defs>
          <linearGradient id="background" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stop-color="#f0f8ed"/>
            <stop offset="0.55" stop-color="#fafcf7"/>
            <stop offset="1" stop-color="#eff6e9"/>
          </linearGradient>
        </defs>
        <rect width="1200" height="630" fill="url(#background)"/>
        <path d="M0 579 C240 526 360 650 658 580 S1010 535 1200 568 V630 H0Z" fill="#e4efdd" opacity="0.55"/>
        <path d="M0 611 C270 555 455 662 740 610 S1030 588 1200 604 V630 H0Z" fill="#dcead5" opacity="0.4"/>
        <g fill="#d7e7cc" opacity="0.5">
          <path d="M1115 0 C1085 34 1103 64 1150 78 C1164 41 1151 14 1115 0Z"/>
          <path d="M1200 31 C1158 26 1136 48 1137 86 C1178 88 1199 68 1200 31Z"/>
          <path d="M1176 99 C1147 105 1141 128 1157 154 C1184 138 1189 120 1176 99Z"/>
        </g>
        <path d="M1163 -12 C1128 39 1125 96 1158 161" fill="none" stroke="#cfdfc5" stroke-width="2" opacity="0.5"/>
        #{title}
        #{icon('calendar-days', y: 306)}
        #{svg_text(date_label, x: 632, y: 337, size: 32)}
        #{icon('clock', y: 378)}
        #{svg_text(time_label, x: 632, y: 409, size: 34)}
        #{icon('map-pin', y: 450)}
        #{svg_text(venue_line, x: 632, y: 481, size: 32)}
        #{svg_text('サークルブック', x: 1152, y: 580, size: 28, color: '#14694e', weight: 'bold', anchor: 'end')}
      </svg>
    SVG
  end
end
