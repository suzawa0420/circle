require 'cgi'

# Explicit prohibited services are rejected. The reported Chinese phrase is
# held for human review regardless of the number of external contacts.
class CircleProfilePolicy
  FIELDS = %i[name appeal goal area schedule requirement cost member recruitment
              contact web line_id twitter instagram item foundation age
              activity_style experience trial equipment meeting_area destination trip_type].freeze
  PROHIBITED = /出張館|密会|援交|デリヘル|風俗|売春|援助|풍속|escort|デリバリーヘルス|ソープランド|ホテヘル|性服務|性服务|外送茶|全套服務|全套服务|性的サービス|sexualservices/
  REVIEW_PHRASE = /深夜舒[壓压]/

  def self.normalized(value)
    ActionView::Base.full_sanitizer.sanitize(CGI.unescapeHTML(value.to_s))
      .unicode_normalize(:nfkc).downcase.gsub(/[[:space:]\p{Cf}\p{P}\p{S}]/, '')
  end

  def self.prohibited?(value)
    normalized(value).match?(PROHIBITED)
  end

  def self.review?(profile)
    FIELDS.any? { |field| normalized(profile.public_send(field)).match?(REVIEW_PHRASE) }
  end
end
