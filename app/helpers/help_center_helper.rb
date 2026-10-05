module HelpCenterHelper
  HELP_ICONS = {
    'account' => ['M8 11V7a4 4 0 0 1 8 0v4', 'M5 11h14v10H5Z', 'M12 15v2'],
    'message' => ['M21 11.5a8.4 8.4 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.4 8.4 0 0 1-3.8-.9L3 21l1.9-5.7a8.4 8.4 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.4 8.4 0 0 1 3.8-.9h.5a8.5 8.5 0 0 1 8 8v.5Z'],
    'listing' => ['M9 5H5a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-4', 'm16 3 5 5-10 10-5 1 1-5Z'],
    'review' => ['m12 3 8 4v5c0 5-8 9-8 9s-8-4-8-9V7Z', 'm9 12 2 2 4-4'],
    'other' => ['M9 9a3 3 0 0 1 6 0c0 2-3 3-3 5', 'M12 18h.01', 'M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0Z'],
    'chevron' => ['m9 5 7 7-7 7']
  }.freeze
  HELP_SHORT_TITLES = {
    'login' => 'ログインできない', 'contact-circle' => '参加・見学したい',
    'no-reply' => '返信が来ない', 'edit-listing' => '募集内容を変更したい'
  }.freeze

  def help_icon(name)
    paths = HELP_ICONS.fetch(name, HELP_ICONS['other'])
    content_tag(:svg, viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor',
      'stroke-width': 1.8, 'stroke-linecap': 'round', 'stroke-linejoin': 'round', 'aria-hidden': true, focusable: false) do
      safe_join(paths.map { |path| content_tag(:path, nil, d: path) })
    end
  end

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
