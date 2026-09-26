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

SitemapGenerator::Sitemap.create do
  current_time = Time.now
  add root_path, :lastmod => current_time, changefreq: 'weekly', priority: 0.3

  # User.find_each do |user|
  #   add circle_path(user), :lastmod => user.updated_at, :priority => 0.3, :changefreq => 'weekly'
    # add "/users/#{user.id}/schedules", :lastmod => current_time, :priority => 0.3, :changefreq => 'weekly'
    # add "/users/#{user.id}/reviews", :lastmod => current_time, :priority => 0.3, :changefreq => 'weekly'
    # add "/users/#{user.id}/questions", :lastmod => current_time, :priority => 0.3, :changefreq => 'weekly'
  # end

  DbKeyword.find_each do |keyword|
    add "/users/kw/#{keyword.keyword}", :lastmod => current_time, :priority => 0.8, :changefreq => 'daily'
  end

  # Blog.find_each do |blog|
  #   add circle_blog_path(blog.user, blog), :lastmod => blog.updated_at, :priority => 0.3, :changefreq => 'weekly'
  # end

  # Schedule.find_each do |schedule|
  #   add user_schedule_path(schedule.user, schedule), :lastmod => schedule.updated_at, :priority => 0.3, :changefreq => 'weekly'
  # end

  # Match.find_each do |match|
  #   add match_path(match), :lastmod => match.updated_at, :priority => 0.5, :changefreq => 'daily'
  # end

  # Tag.find_each do |tag|
  #   add "/tag/#{tag.id}", :lastmod => current_time, :priority => 0.5, :changefreq => 'weekly'
  # end

  # Prefecture.find_each do |prefecture|
  #   if prefecture.kana != "nil"
      # add "/prefectures/#{prefecture.kana}", :lastmod => current_time, :priority => 0.8, :changefreq => 'daily'
      # add "/blog/prefectures/#{prefecture.kana}", :lastmod => current_time, :priority => 0.3, :changefreq => 'weekly'
      # # add "/match/prefectures/#{prefecture.kana}", :lastmod => current_time, :priority => 0.3, :changefreq => 'weekly'

      # Tag.find_each do |prefecture_tag|
      #   add "/prefectures/#{prefecture.kana}/tag/#{prefecture_tag.id}", :lastmod => current_time, :priority => 0.5, :changefreq => 'weekly'
      # end

      # City.where(prefecture_id: prefecture.id).find_each do |prefecture_city|
      #   add "/prefectures/#{prefecture.kana}/#{prefecture_city.city_kana}", :lastmod => current_time, :priority => 0.8, :changefreq => 'daily'

      #   Station.where(city_id: prefecture_city.id).find_each do |prefecture_station|
      #     add "/prefectures/#{prefecture.kana}/#{prefecture_city.city_kana}/#{prefecture_station.id}", :lastmod => current_time, :priority => 0.5, :changefreq => 'daily'
      #   end

        # Tag.find_each do |prefecture_city_tag|
        #   add "/prefectures/#{prefecture.kana}/#{prefecture_city.city_kana}/tag/#{prefecture_city_tag.id}", :lastmod => current_time, :priority => 0.5, :changefreq => 'weekly'
        # end
  #     end

  #   end
  # end

  # Event.find_each do |event|

  #   if event.ruby != "nil"
  #     add "/#{event.ruby}", :lastmod => current_time, :priority => 0.8, :changefreq => 'daily'
  #     add "blog/#{event.ruby}", :lastmod => current_time, :priority => 0.3, :changefreq => 'weekly'

  #     if event.place == 1
  #       add "places/#{event.ruby}", :lastmod => current_time, :priority => 0.5, :changefreq => 'weekly'
  #     end

  #     Tag.find_each do |event_tag|
  #       add "/#{event.ruby}/tag/#{event_tag.id}", :lastmod => current_time, :priority => 0.5, :changefreq => 'weekly'
  #     end

  #     Prefecture.find_each do |event_prefecture|
  #       if event_prefecture.kana != "nil"
          # add "/#{event.ruby}/#{event_prefecture.kana}", :lastmod => current_time, :priority => 1.0, :changefreq => 'daily'
          # add "blog/#{event.ruby}/#{event_prefecture.kana}", :lastmod => current_time, :priority => 0.3, :changefreq => 'weekly'

          # if event.place == 1
          #   add "places/#{event.ruby}/#{event_prefecture.kana}", :lastmod => current_time, :priority => 0.5, :changefreq => 'weekly'
          # end

          # Tag.find_each do |event_prefecture_tag|
          #   add "/#{event.ruby}/#{event_prefecture.kana}/tag/#{event_prefecture_tag.id}", :lastmod => current_time, :priority => 0.5, :changefreq => 'weekly'
          # end

          # City.where(prefecture_id: event_prefecture.id).find_each do |city|
            # add "/#{event.ruby}/#{event_prefecture.kana}/#{city.city_kana}", :lastmod => current_time, :priority => 0.8, :changefreq => 'daily'

            # if event.place == 1
            #   add "places/#{event.ruby}/#{event_prefecture.kana}/#{city.city_kana}", :lastmod => current_time, :priority => 0.5, :changefreq => 'weekly'
            # end

            # Station.where(city_id: city.id).find_each do |event_station|
            #   add "/#{event.ruby}/#{event_prefecture.kana}/#{city.city_kana}/#{event_station.id}", :lastmod => current_time, :priority => 0.5, :changefreq => 'daily'
            # end

            # Tag.find_each do |event_city_tag|
            #   add "/#{event.ruby}/#{event_prefecture.kana}/#{city.city_kana}/tag/#{event_city_tag.id}", :lastmod => current_time, :priority => 0.5, :changefreq => 'weekly'
            # end

  #         end
  #       end
  #     end
  #   end

  # end

  # Category.find_each do |category|
  #   add "/categories/#{category.kana}", :lastmod => current_time, :priority => 0.5, :changefreq => 'daily'

  #   Prefecture.find_each do |c_prefecture|
  #     add "/categories/#{category.kana}/#{c_prefecture.kana}", :lastmod => current_time, :priority => 0.5, :changefreq => 'daily'
  #   end

  # end



  # Event.where.not(matching: 0).find_each do |m_event|
  #   add "/match/#{m_event.ruby}", :lastmod => current_time, :priority => 0.5, :changefreq => 'daily'

  #   Prefecture.find_each do |m_prefecture|
  #     add "/match/#{m_event.ruby}/#{m_prefecture.kana}", :lastmod => current_time, :priority => 0.5, :changefreq => 'daily'
  #   end

  # end

end
