module WebmasterNavigationHelper
  def webmaster_navigation_items
    # Count current pending work, without including resolved or blocked records.
    support_counts = SupportRequest.where(status: 'pending').group(:kind).count
    [
      ['お問い合わせ', super_admin_support_requests_path, support_counts.except('suggestion').values.sum],
      ['通報', super_admin_chat_reports_path, ChatReport.where(status: 'pending').count],
      ['スパム確認', super_admin_chat_moderations_path, ChatMessage.where(moderation_status: 'held').count],
      ['ご意見箱', super_admin_opinions_path, support_counts.fetch('suggestion', 0)],
      ['欠席申告', super_admin_no_show_reports_path, NoShowReport.where(status: 'pending').count],
      ['施設修正依頼', super_admin_place_information_reports_path, PlaceInformationReport.where(status: 'pending').count],
      ['リンク設置申請', super_admin_backlink_requests_path, BacklinkRequest.where(status: 'pending').count],
      ['投稿確認', super_admin_circles_path(anchor: 'pending-posts'),
       User.where(moderation_status: 'review').count + Blog.where(moderation_status: 'review').count + PlaceReview.where(moderation_status: 'review').count],
      ['管理トップ', webmaster_path, 0],
      ['メッセージ', super_admin_conversations_path, 0],
      ['口コミ', super_admin_reviews_path, 0],
      ['施設', super_admin_places_path, 0],
      ['コラム', columns_path, 0],
      ['ブロック', account_blocks_path, 0],
      ['無効メール', invalid_emails_path, 0],
      ['検索キーワード', db_keywords_path, 0],
      ['入力エラー', db_validation_errors_path, 0],
      ['サークル・主催者', super_admin_circles_path, 0],
      ['参加者管理', super_admin_accounts_path, 0]
    ]
  end
end
