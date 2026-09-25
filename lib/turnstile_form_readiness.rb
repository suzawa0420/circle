require 'nokogiri'

module TurnstileFormReadiness
  def self.ready?(status:, body:)
    return false unless status.to_i == 200
    document = Nokogiri::HTML(body)
    widget = document.at_css('form .registration-turnstile[data-sitekey]')
    widget && !widget['data-sitekey'].to_s.strip.empty?
  end
end
