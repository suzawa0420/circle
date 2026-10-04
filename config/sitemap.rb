require 'aws-sdk-s3'

# Set the host name for URL creation
SitemapGenerator::Sitemap.default_host = 'https://circle-book.com'
SitemapGenerator::Sitemap.sitemaps_host = "https://s3-ap-northeast-1.amazonaws.com/#{ENV['AWS_S3_BUCKET']}"
SitemapGenerator::Sitemap.sitemaps_path = 'sitemaps/'
SitemapGenerator::Sitemap.adapter = SitemapGenerator::AwsSdkAdapter.new(
  ENV['AWS_S3_BUCKET'],
  aws_access_key_id: ENV['AWS_IAM_ACCESS_KEY_ID'],
  aws_secret_access_key: ENV['AWS_IAM_ACCESS_KEY'],
  aws_region: ENV['AWS_S3_REGION'],
)

# ▼SEOの観点
# 1.0 最重要
# 0.8 高
# 0.5 中
# 0.3 低

SitemapGenerator::Sitemap.create(create_index: true, include_root: false) do
  add root_path, lastmod: nil, changefreq: 'weekly', priority: 0.3

  User.publicly_visible.find_each do |user|
    add circle_path(user), :lastmod => user.updated_at, :priority => 0.3, :changefreq => 'weekly'
  end

  # Only populated, canonical landing pages belong in the sitemap. Arbitrary
  # internal search terms and sort/date combinations are deliberately omitted.
  population = User.publicly_visible
  Event.where(id: population.select(:event_id)).find_each do |event|
    next if event.ruby.blank? || event.ruby == 'nil'
    add event_path(event.ruby), lastmod: nil, changefreq: 'daily', priority: 0.8
    Prefecture.where(id: population.where(event_id: event.id).select(:prefecture_id)).find_each do |prefecture|
      next if prefecture.kana.blank? || prefecture.kana == 'nil'
      add event_prefecture_path(event.ruby, prefecture.kana), lastmod: nil, changefreq: 'daily', priority: 0.8
    end
  end
  Prefecture.where(id: population.select(:prefecture_id)).find_each do |prefecture|
    next if prefecture.kana.blank? || prefecture.kana == 'nil'
    add prefecture_path(prefecture.kana), lastmod: nil, changefreq: 'daily', priority: 0.8
  end
end
