require 'cgi'
require 'digest'

# Explicit prohibited services are rejected. Euphemistic service promotions
# are held for human review regardless of the number of external contacts.
class CircleProfilePolicy
  FIELDS = %i[name appeal goal area schedule requirement cost member recruitment
              contact web line_id twitter instagram item foundation age
              activity_style experience trial equipment meeting_area destination trip_type].freeze
  PROHIBITED = /出張館|密会|援交|デリヘル|風俗|売春|援助|풍속|escort|デリバリーヘルス|ソープランド|ホテヘル|性服務|性服务|外送茶|全套服務|全套服务|性的サービス|sexualservices/
  REVIEW_PHRASE = /深夜舒[壓压]|(?:高品質な?|高級な?|厳選された)デリバリーサービス/
  DISGUISED_SOLICITATION = 'disguised_romantic_solicitation'.freeze
  DISGUISED_ADULT_SERVICE = 'disguised_adult_service_promotion'.freeze
  FINGERPRINTED_REASONS = [DISGUISED_SOLICITATION, DISGUISED_ADULT_SERVICE].freeze
  DISPATCH_SERVICE = /高級出張|出張サービス|出張派遣|女性派遣/
  PERSON_DELIVERY = /(?:女性|女の子|美女|キャスト)(?:を|が).{0,32}(?:お届け|おとどけ|派遣|伺う|伺い)/
  PRIVATE_DESTINATION = /自宅|ホテル|宿泊先|お部屋/
  PRIVATE_COMPANIONSHIP = /夜のひととき|夜を一人で過ごしたくない|女性との時間|\d+名(?:以上)?の(?:女性|女の子)|(?:女性|女の子|キャスト)からお選び/
  ROMANTIC_INTENT = /恋人募集|恋愛相手|恋愛目的|異性との出会い|浪漫[愛爱]情|[尋寻]找[愛爱]情|romanticrelationship|romanticpartner/
  INVITATION = /募集|探して|探す|参加|加入|[歡欢]迎|[尋寻]找|lookingfor|join/
  GENERAL_EVENTS = %w[event gathering meet-up chat student-group study english other].freeze
  ACTIVITY_ALIASES = {
    'fishing' => %w[釣り 釣行 釣魚 钓鱼 フィッシング fishing アジング エギング],
    'basketball' => %w[バスケ バスケット basketball 籃球 篮球],
    'baseball' => %w[野球 baseball], 'volleyball' => %w[バレー volleyball],
    'reading' => %w[読書 本を読む reading], 'mountain' => %w[登山 山登り ハイキング hiking]
  }.freeze

  def self.normalized(value)
    ActionView::Base.full_sanitizer.sanitize(CGI.unescapeHTML(value.to_s))
      .unicode_normalize(:nfkc).downcase.gsub(/[[:space:]\p{Cf}\p{P}\p{S}]/, '')
  end

  def self.prohibited?(value)
    normalized(value).match?(PROHIBITED) || prohibited_promotion?(value)
  end

  def self.prohibited_promotion?(value)
    normalized(value).include?('日本椿兔')
  end

  def self.review?(profile)
    FIELDS.any? { |field| normalized(profile.public_send(field)).match?(REVIEW_PHRASE) }
  end

  # Hold the combination for review, not ordinary travel, hotels or female-led
  # activities. Naming a hobby/category does not excuse this dispatch promotion.
  def self.adult_dispatch_promotion?(profile)
    text = FIELDS.map { |field| profile.public_send(field).to_s }.join("\n")
    plain = normalized(text)
    plain.match?(DISPATCH_SERVICE) && plain.match?(PERSON_DELIVERY) &&
      plain.match?(PRIVATE_DESTINATION) && plain.match?(PRIVATE_COMPANIONSHIP) &&
      external_destination?(profile, text)
  end

  def self.fingerprinted_review?(profile)
    disguised_solicitation?(profile) || adult_dispatch_promotion?(profile)
  end

  # A narrow review signal, never a verdict: explicit romantic recruitment,
  # an external destination and no mention of the selected concrete hobby.
  # Generic social/learning categories are intentionally outside this rule.
  def self.disguised_solicitation?(profile)
    text = FIELDS.map { |field| profile.public_send(field).to_s }.join("\n")
    normalized_text = normalized(text)
    return false unless normalized_text.match?(ROMANTIC_INTENT) && normalized_text.match?(INVITATION)
    return false unless external_destination?(profile, text)

    event = profile.event
    return false unless event && event.category_id != 8 && !GENERAL_EVENTS.include?(event.ruby)

    aliases = ACTIVITY_ALIASES.fetch(event.ruby) { event.name.to_s.split(/[・\/／]/) + [event.ruby] }
    aliases.compact.reject(&:blank?).none? { |word| normalized_text.include?(normalized(word)) }
  end

  def self.external_destination?(profile, text)
    return true if %i[web line_id twitter instagram].any? { |field| profile.public_send(field).present? }

    plain = ActionView::Base.full_sanitizer.sanitize(CGI.unescapeHTML(text))
      .unicode_normalize(:nfkc).downcase.gsub(/[[:space:]\p{Cf}]/, '')
    plain.match?(%r{https?://|(?:telegram|tg|gleezy|discord|line)[:@][a-z0-9_@.-]{3,}})
  end

  def self.solicitation_fingerprint(profile)
    Digest::SHA256.hexdigest(([profile.event_id] + FIELDS.map { |field| normalized(profile.public_send(field)) }).to_json)
  end
end
