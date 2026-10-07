class ChatMailer < ApplicationMailer
  def new_messages(conversation, role)
    @conversation = conversation
    recipient = role == 'member' ? conversation.member.email : conversation.user.admin_user.email
    circle_name = conversation.user.name.to_s.squish.presence || 'サークル'
    subject = if role == 'member'
      "【サークルブック｜#{circle_name}】主催者からメッセージが届きました"
    else
      member_name = conversation.member.nickname.to_s.squish.presence || 'メンバー'
      "【サークルブック｜#{circle_name}】#{member_name}さんからメッセージが届きました"
    end
    mail(to: recipient, subject: subject)
  end

  def verify_owner_email(owner)
    @token = owner.signed_id(purpose: owner.email_verification_purpose, expires_in: 24.hours)
    mail(to: owner.email, subject: '【サークルブック】主催者メールアドレスの確認')
  end

  def verify_email(member)
    @token = member.signed_id(purpose: member.email_verification_purpose, expires_in: 24.hours)
    mail(to: member.email, subject: '【サークルブック】メールアドレスの確認')
  end
end
