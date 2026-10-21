class ColumnProduct < ApplicationRecord
  belongs_to :column, inverse_of: :column_products, touch: true
  validates :name, presence: true, length: { maximum: 200 }
  validates :description, length: { maximum: 2000 }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 999 }
  validate :valid_shop_links

  private

  def valid_shop_links
    errors.add(:base, '商品にはAmazonかメルカリの紹介リンクを入力してください。') if amazon_url.blank? && mercari_url.blank?
    %i[amazon_url mercari_url].each do |attribute|
      next if self[attribute].blank?
      self[attribute] = self[attribute].strip
      uri = URI.parse(self[attribute]) rescue nil
      hosts = attribute == :amazon_url ? %w[amazon.co.jp www.amazon.co.jp amzn.to] : %w[jp.mercari.com mercari.com www.mercari.com mercari-shops.com www.mercari-shops.com merc.li]
      unless uri.is_a?(URI::HTTPS) && hosts.include?(uri.host&.downcase) && uri.userinfo.nil? && uri.port == 443
        errors.add(attribute, 'にはショップで発行したhttpsの紹介リンクを入力してください。')
      end
    end
  end
end
