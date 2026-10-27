class ChatMailer < ApplicationMailer
  def new_messages(conversation, role)
    @conversation = conversation
    recipient = conversation.actor(role).email
    circle_name = notification_circle_name(conversation.user)
    subject = if conversation.practice_match?
      other_role = role == 'member' ? 'owner' : 'member'
      "【サークルブック｜練習試合】#{notification_circle_name(conversation.person(other_role))}からメッセージが届きました"
    elsif role == 'member'
      "【サークルブック｜#{circle_name}】主催者からメッセージが届きました"
    else
      member_name = conversation.member.nickname.to_s.squish.presence || 'メンバー'
      "【サークルブック｜#{circle_name}】#{member_name}さんからメッセージが届きました"
    end
    mail(to: recipient, subject: subject)
  end

  def review_received(conversation, role)
    @conversation = conversation
    circle_name = notification_circle_name(conversation.user)
    mail(to: conversation.actor(role).email, subject: "【サークルブック｜#{circle_name}】相手から口コミが届いています")
  end

  def verify_owner_email(owner)
    @token = owner.signed_id(purpose: owner.email_verification_purpose, expires_in: 24.hours)
    mail(to: owner.email, subject: '【サークルブック】主催者メールアドレスの確認')
  end

  def verify_email(member)
    @token = member.signed_id(purpose: member.email_verification_purpose, expires_in: 24.hours)
    mail(to: member.email, subject: '【サークルブック】メールアドレスの確認')
  end

  private

  def notification_circle_name(circle)
    circle.publicly_visible? ? (circle.name.to_s.squish.presence || 'サークル') : 'サークル'
  end
end
