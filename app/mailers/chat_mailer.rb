class ChatMailer < ApplicationMailer
  def new_messages(conversation, role)
    @conversation = conversation
    recipient = role == 'member' ? conversation.member.email : conversation.user.admin_user.email
    mail(to: recipient, subject: '【サークルブック】新しいメッセージが届いています')
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
