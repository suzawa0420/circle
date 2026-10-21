class ColumnProduct < ApplicationRecord
  belongs_to :column, inverse_of: :column_products, touch: true
  validates :name, presence: true, length: { maximum: 200 }
  validates :description, length: { maximum: 2000 }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 999 }
  validate :valid_shop_links
  validate :valid_image_url

  def valid_amazon_image_url?
    uri = URI.parse(image_url.to_s) rescue nil
    uri.is_a?(URI::HTTPS) && uri.host == 'm.media-amazon.com' &&
      uri.port == 443 && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? &&
      uri.path.match?(%r{\A/images/I/[A-Za-z0-9+,%._-]+\.(?:jpe?g|png|webp)\z}i)
  end

  private

  def valid_image_url
    return if image_url.blank?
    self.image_url = image_url.strip
    errors.add(:image_url, 'にはAmazonが提供する商品画像のhttps URLを入力してください。') unless amazon_url.present? && image_url.length <= 2048 && valid_amazon_image_url?
  end

  def valid_shop_links
    errors.add(:base, '商品にはAmazonの紹介リンクを入力してください。') if amazon_url.blank?
    %i[amazon_url].each do |attribute|
      next if self[attribute].blank?
      self[attribute] = self[attribute].strip
      uri = URI.parse(self[attribute]) rescue nil
      hosts = %w[amazon.co.jp www.amazon.co.jp amzn.to]
      unless uri.is_a?(URI::HTTPS) && hosts.include?(uri.host&.downcase) && uri.userinfo.nil? && uri.port == 443
        errors.add(attribute, 'にはショップで発行したhttpsの紹介リンクを入力してください。')
      end
    end
  end
end
