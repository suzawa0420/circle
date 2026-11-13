require 'uri'
require 'ipaddr'
require 'nokogiri'

module PlaceImports
  # Discovery only: a candidate is NOT verified facility data or permission to publish.
  # The injected client must enforce time/size limits, no redirects and public DNS.
  class OfficialDiscoveryCrawler
    MAX_PAGES = 3
    MAX_URLS = 2_000
    MAX_BODY_BYTES = 2 * 1024 * 1024
    MAX_ATTEMPTS = 2
    SPORTS = /体育館|体育センター|運動公園|スポーツ(?:施設|センター|公園)|テニス(?:コート|場)|庭球場|球技場|競技場|sports?|taiiku|gym(?:nasium)?|tennis|undou|undō/i
    ERROR_CODES = %w[robots_unavailable robots_disallowed fetch_failed invalid_document capacity_reached].freeze

    def initialize(config:, client:)
      @prefecture = config.fetch('prefecture') { config.fetch(:prefecture) }
      @root = config.fetch('root') { config.fetch(:root) }
      @client = client
      @entrypoints = Array(config['entrypoints'] || config[:entrypoints]).first(20)
      uri = URI.parse(@root)
      @host = uri.host
      raise ArgumentError, 'invalid official root' unless approved?(uri) && ['', '/'].include?(uri.path)
      @root = "https://#{@host}/"
    rescue URI::InvalidURIError
      raise ArgumentError, 'invalid official root'
    end

    def call(state: {}, rescan: false)
      @state = rescan ? empty_state : normalize_state(state)
      result = { state: @state, candidates: [], counters: { fetched: 0, blocked: 0, failed: 0 }, errors: [] }
      return result if @state['complete']
      result[:errors] << 'capacity_reached' if @state['capacity_reached']
      begin
        robots = body(@client.get("https://#{@host}/robots.txt"))
        raise ArgumentError, 'invalid robots' if robots.include?('<') || robots.include?('>')
      rescue StandardError
        result[:errors] << 'robots_unavailable'
        return result
      end
      rules = robots_rules(robots)
      unless @state['initialized']
        enqueue(@root, result)
        @entrypoints.each { |url| enqueue(url, result) }
        robots.each_line do |line|
          value = line.sub(/#.*/, '').match(/^\s*Sitemap:\s*(\S+)\s*$/i)&.[](1)
          enqueue(value, result) if value
        end
        @state['initialized'] = true
      end
      MAX_PAGES.times do
        url = @state['frontier'].shift
        break unless url
        @current_url = url
        path = URI.parse(url).path
        if rules.any? { |rule| rule.match?(path) || rule.match?(URI::DEFAULT_PARSER.unescape(path)) }
          finish(url)
          result[:counters][:blocked] += 1
          result[:errors] << 'robots_disallowed'
          next
        end
        begin
          content = body(@client.get(url))
          result[:counters][:fetched] += 1
          inspect_page(url, content, result)
          finish(url)
        rescue StandardError
          result[:counters][:failed] += 1
          result[:errors] << 'fetch_failed'
          attempts = @state['attempts'].fetch(url, 0) + 1
          if attempts < MAX_ATTEMPTS
            @state['attempts'][url] = attempts
            @state['frontier'] << url
          else
            finish(url)
          end
        end
      end
      @state['complete'] = @state['frontier'].empty?
      @current_url = nil
      result[:errors].uniq!
      result[:candidates].uniq! { |candidate| candidate['url'] }
      result
    end

    private

    def empty_state
      { 'frontier' => [], 'seen' => [], 'attempts' => {}, 'initialized' => false,
        'complete' => false, 'capacity_reached' => false }
    end

    def normalize_state(input)
      s = empty_state
      %w[frontier seen].each do |key|
        s[key] = Array(input[key]).filter_map { |url| safe_url(url) }.uniq.first(MAX_URLS)
      end
      s['frontier'] -= s['seen']
      # Never allow hostile stored state to create an unbounded crawl.
      remaining = MAX_URLS - s['seen'].size
      s['frontier'] = s['frontier'].first(remaining)
      s['attempts'] = s['frontier'].to_h do |url|
        n = input.fetch('attempts', {})[url]
        [url, n.is_a?(Integer) ? [[n, 0].max, MAX_ATTEMPTS].min : 0]
      end
      %w[initialized complete capacity_reached].each { |key| s[key] = input[key] == true }
      s
    end

    def approved?(uri)
      host = uri.host.to_s.downcase
      return false if host.empty? || host != @host || host == 'localhost' || host.match?(/(?:\A|\.)(?:local|internal|localhost)\z/)
      begin
        IPAddr.new(host)
        return false # Literal addresses are never official crawling roots.
      rescue IPAddr::InvalidAddressError
        # DNS resolution and rebinding protection remain the client's responsibility.
      end
      uri.scheme == 'https' && uri.port == 443 && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? &&
        host.end_with?('.jp') && !uri.path.match?(/[\x00-\x20\\]|%25/i)
    end

    def safe_url(value, base = @root)
      return nil unless value.is_a?(String) && value.bytesize <= 2_048
      uri = URI.join(base, value)
      approved?(uri) ? uri.to_s : nil
    rescue URI::Error
      nil
    end

    def enqueue(value, result, base = @root)
      url = safe_url(value, base)
      return unless url
      return if @state['seen'].include?(url) || @state['frontier'].include?(url)
      if @state['seen'].size + @state['frontier'].size + (@current_url ? 1 : 0) >= MAX_URLS
        @state['capacity_reached'] = true
        result[:errors] << 'capacity_reached'
      else
        @state['frontier'] << url
      end
    end

    def finish(url)
      @state['seen'] << url unless @state['seen'].include?(url)
      @state['attempts'].delete(url)
    end

    def body(value)
      raise ArgumentError, 'invalid body' unless value.is_a?(String) && value.bytesize <= MAX_BODY_BYTES
      text = value.dup.force_encoding(Encoding::UTF_8)
      raise ArgumentError, 'invalid encoding' unless text.valid_encoding?
      text
    end

    def robots_rules(text)
      text.each_line.filter_map do |line|
        rule = line.sub(/#.*/, '').match(/^\s*Disallow:\s*(\S+)/i)&.[](1)
        next unless rule
        Regexp.new('\\A' + Regexp.escape(rule).gsub('\\*', '.*').sub(/\\\$\z/, '\\z'))
      end
    end

    def inspect_page(url, content, result)
      if content.lstrip.start_with?('<?xml', '<urlset', '<sitemapindex')
        # NONET; never expand entities or fetch external DTDs.
        doc = Nokogiri::XML(content) { |options| options.strict.nonet }
        raise ArgumentError, 'unsupported xml' unless %w[urlset sitemapindex].include?(doc.root&.name)
        is_index = doc.root.name == 'sitemapindex'
        doc.xpath('//*[local-name()="loc"]').each do |node|
          value = node.text.strip
          enqueue(value, result, url) if is_index || value.match?(SPORTS)
        end
        return
      end
      doc = Nokogiri::HTML(content)
      doc.css('script,style,form').remove
      title = doc.at_css('h1')&.text.to_s.gsub(/[[:space:]]+/, ' ').strip
      title = doc.at_css('title')&.text.to_s.gsub(/[[:space:]]+/, ' ').strip if title.empty?
      if title.match?(SPORTS)
        result[:candidates] << { 'url' => url, 'name' => title[0, 200], 'prefecture' => @prefecture }
      end
      doc.css('a[href]').each do |link|
        value = link['href']
        enqueue(value, result, url) if "#{link.text} #{value}".match?(SPORTS)
      end
    end
  end
end
