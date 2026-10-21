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

  if Column.published.exists?
    add columns_path, changefreq: 'weekly', priority: 0.5
    Column.published.find_each do |column|
      add column_path(column), lastmod: column.updated_at, changefreq: 'monthly', priority: 0.5
    end
  end

  User.publicly_visible.find_each do |user|
    add circle_path(user), :lastmod => user.updated_at, :priority => 0.3, :changefreq => 'weekly'
  end

  # Only populated, canonical landing pages belong in the sitemap. Arbitrary
  # internal search terms and sort/date combinations are deliberately omitted.
  population = User.publicly_visible
  Event.find_each do |event|
    sport_users = population.for_event(event.id)
    next unless sport_users.exists?
    next if event.ruby.blank? || event.ruby == 'nil'
    add event_path(event.ruby), lastmod: nil, changefreq: 'daily', priority: 0.8
    Prefecture.where(id: sport_users.select(:prefecture_id)).or(Prefecture.where(id: sport_users.select(:prefecture_sub_id))).find_each do |prefecture|
      next if prefecture.kana.blank? || prefecture.kana == 'nil'
      add event_prefecture_path(event.ruby, prefecture.kana), lastmod: nil, changefreq: 'daily', priority: 0.8
    end
  end
  Prefecture.where(id: population.select(:prefecture_id)).find_each do |prefecture|
    next if prefecture.kana.blank? || prefecture.kana == 'nil'
    add prefecture_path(prefecture.kana), lastmod: nil, changefreq: 'daily', priority: 0.8
  end
  CircleFilterLanding.each_populated_path do |path|
    add path, lastmod: nil, changefreq: 'daily', priority: 0.6
  end

  CircleCityDirectory.each_populated_path do |path|
    add path, lastmod: nil, changefreq: 'daily', priority: 0.7
  end

  EventDaySitemap.each_path do |path|
    add path, lastmod: nil, changefreq: 'daily', priority: 0.7
  end
  EventDayListing.public_schedules.where(day: Time.current.in_time_zone('Tokyo').to_date.iso8601..'2100-12-31')
    .select(:id, :user_id, :updated_at).find_each do |schedule|
    add user_schedule_path(schedule.user_id, schedule.id), lastmod: schedule.updated_at, priority: 0.6
  end

end

# Public XML uses a persistent cache. Invalidate only sitemap responses after
# successful generation/upload on the generating server. Other app servers
# refresh via the short cache TTL in SitemapsController.
Rails.cache.delete_matched(/\Apublished-sitemap-v2\//)
