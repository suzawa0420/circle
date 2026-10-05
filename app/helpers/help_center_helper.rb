module HelpCenterHelper
  def help_action(article)
    case article[:action]
    when :circles then ['サークルを探す', circles_path]
    when :login then ['ログイン画面を選ぶ', login_path]
    when :messages then ['メッセージ一覧を開く', conversations_path]
    when :owner_dashboard
      circle = current_admin_user&.users&.first
      circle ? ['主催者管理画面を開く', "/users/#{circle.id}/mypage"] : ['主催者ログイン', new_admin_user_session_path]
    when :withdraw_member then ['参加者の退会手続き', unsubscribe_member_path]
    when :withdraw_owner then ['主催者の退会手続き', unsubscribe_admin_user_path]
    when :account
      admin_user_signed_in? ? ['主催者のアカウント設定', edit_admin_user_registration_path] : ['参加者のアカウント設定', edit_member_registration_path]
    when :suggestion then ['ご意見箱を開く', new_support_request_path(kind: 'suggestion', category: 'other')]
    else ['運営への問い合わせ', new_support_request_path(category: article[:category])]
    end
  end
end
