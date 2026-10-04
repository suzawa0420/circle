module ApplicationHelper

  def fast_public_listing?
    public_search_listing? && !admin_user_signed_in? && !member_signed_in? && !webmaster? && !exhibition_group_signed_in?
  end

  def circle_listing_header_image(user, first: false)
    image_tag user.pic_header.url, class: 'header_imege_user_list',
      alt: "#{user.name}の活動紹介", loading: first ? 'eager' : 'lazy',
      fetchpriority: first ? 'high' : 'auto', decoding: 'async'
  end

  def circle_listing_description
    area = [@prefecture&.name, @city&.name].compact.join
    activity = @event&.txt.presence || 'サークル・チーム'
    audience = @event&.ruby == 'student-group' ? '参加できる大学・学年などの条件' : '初心者の参加条件や募集対象'
    "#{area.present? ? "#{area}の" : "全国の"}#{activity}を活動場所・日程・募集内容から比較。#{audience}、費用は各団体の詳細で確認できます。気になる団体の活動予定を見て、参加について問い合わせましょう。"
  end

  def account_access_form_page?
    %w[admin_users/sessions admin_users/registrations members/sessions members/registrations].include?(controller_path) &&
      %w[new create].include?(action_name)
  end

  def admax_public_page?
    return false if webmaster?
    public_controller = %w[home categories matches schedules questions tags events prefectures places columns].include?(controller_path) ||
                        controller_path.start_with?('circles/', 'blogs/')
    return true if controller_path == "conversations" && %w[index show].include?(action_name)
    public_controller && %w[index show dates day event prefecture event_prefecture category category_prefecture].include?(action_name)
  end

  def default_meta_tags
      {
        site: "サークルブック",
        title: "サークルブック",
        reverse: true,
        charset: "utf-8",
        description: "【完全無料／登録不要】47都道府県のサークルやチーム、団体のメンバー募集サイトです！スポーツや趣味など豊富に掲載！10代〜60代、社会人や学生、初心者、経験者など、誰でも参加可能！バスケやバレー、フットサルなど。無料で簡単にメンバー募集ができます！",
        keywords: "サークル,チーム,団体,スポーツ,趣味,社会人,学生",
        separator: "|",
        icon: [
          { href: image_url("/images/favicon.ico?v=20260921-green-clean"), type: "image/x-icon", sizes: "16x16 32x32 48x48" },
          { href: image_url("/images/favicon-48.png?v=20260921-green-clean"), type: "image/png", sizes: "48x48" },
          { href: image_url("/images/apple-touch-icon.png?v=20260921-green-clean"), rel: "apple-touch-icon", sizes: "180x180", type: "image/png" },
        ],
        og: {
          site_name: :site,
          title: :title,
          description: :description,
          type: "website",
          url: request.original_url,
          image: image_url("/images/ogp.png?v=20260921-green-clean"),
          locale: "ja_JP"
        },
        twitter: {
            card: "summary_large_image"
        }
      }
  end

    def lazysizes_image_tag(source, options={})
      options['data-src'] = source
      if options[:class].blank?
        options[:class] = "lazyload"
      else
        options[:class] = "lazyload #{options[:class]}"
      end
      image_tag("/images/loading.gif", options) + ("<noscript>#{image_tag(source, options)}</noscript>").html_safe
    end





end
