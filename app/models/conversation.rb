class Conversation < ApplicationRecord
  class NotAllowed < StandardError; end
  before_validation :assign_public_id, on: :create
  attr_readonly :public_id

  def to_param
    public_id
  end

  def assign_public_id
    return if public_id.present?
    loop do
      self.public_id = SecureRandom.alphanumeric(24)
      break unless public_id.match?(/\A\d+\z/) || self.class.exists?(public_id: public_id)
    end
  end

  ROLES = %w[member owner].freeze
  belongs_to :user
  belongs_to :member
  has_many :chat_messages, dependent: :destroy
  has_many :conversation_reviews, dependent: :destroy
  has_many :chat_reports, dependent: :destroy

  def self.for_member!(user, member)
    raise NotAllowed, '利用停止中のため、新しい問い合わせはできません。' if member.reload.suspended? || user.admin_user.reload.suspended?
    create_or_find_by!(user: user, member: member) do |conversation|
      conversation.legacy_member_review = Review.exists?(user: user, member: member)
    end
  end

  def ensure_active_sender!(role)
    raise NotAllowed, '送信者が不正です。' unless ROLES.include?(role)
    actor = role == 'owner' ? user.admin_user : member
    raise NotAllowed, '利用停止中はメッセージ・口コミを投稿できません。' if actor.reload.suspended?
  end

  def blocked?
    member_blocked? || owner_blocked?
  end

  def send_message!(role, body)
    with_lock do
      raise NotAllowed, 'ブロック中はメッセージを送信できません。' if blocked?
      ensure_active_sender!(role)
      sender = role == 'owner' ? user.admin_user : member
      raise NotAllowed, 'メールアドレスを確認してください。' unless sender.email_verified?
      if chat_messages.where(sender_role: role).where('created_at > ?', 1.minute.ago).count >= 10
        raise NotAllowed, '送信が続いています。少し待ってからお試しください。'
      end
      if role == 'owner' && !chat_messages.where(sender_role: 'member').exists?
        raise NotAllowed, '参加者からの問い合わせを受けてから返信できます。'
      end
      if role == 'member' && !chat_messages.exists?
        CircleInquiryGuidance.new(user).messages.each do |guidance|
          chat_messages.create!(sender_role: 'system', body: guidance)
        end
      end
      message = chat_messages.create!(sender_role: role, body: body)
      if role == 'owner' && accepted_at.nil?
        self.accepted_at = Time.current
        self.review_deadline = 14.days.from_now
        had_no_reply_report = respond_check == "NG"
        self.respond_check = nil
      end
      recipient = role == 'member' ? 'owner' : 'member'
      due_key = "#{recipient}_notification_due_at"
      last_notified = self["#{recipient}_notified_at"]
      self[due_key] ||= [5.minutes.from_now, last_notified && last_notified + 15.minutes].compact.max
      save!
      refresh_circle_score! if had_no_reply_report
      message
    end
  end

  def mark_read!(role, through:)
    with_lock do
      self["#{role}_read_message_id"] = [self["#{role}_read_message_id"], through].max
      incoming_role = role == 'member' ? 'owner' : 'member'
      unless chat_messages.where(sender_role: incoming_role).where('id > ?', self["#{role}_read_message_id"]).exists?
        self["#{role}_notification_due_at"] = nil
      end
      update_columns("#{role}_read_message_id" => self["#{role}_read_message_id"],
                     "#{role}_notification_due_at" => self["#{role}_notification_due_at"])
    end
  end

  def submit_review!(role, attributes)
    with_lock do
      ensure_active_sender!(role)
      publish_reviews_locked!
      raise NotAllowed, '評価の投稿期間外です。' unless accepted_at && review_deadline > Time.current && reviews_published_at.nil?
      if role == 'member' && (legacy_member_review? || Review.exists?(user: user, member: member))
        raise NotAllowed, 'このサークルへの評価はすでに投稿済みです。'
      end
      review = conversation_reviews.find_or_initialize_by(author_role: role)
      raise NotAllowed, '公開後の評価は編集・再投稿できません。' if review.published_at || review.deleted_at
      review.assign_attributes(attributes)
      review.participated = false if role == 'owner'
      review.save!
      publish_reviews_locked!
      review
    end
  end

  def delete_review!(role)
    with_lock do
      publish_reviews_locked!
      review = conversation_reviews.find_by!(author_role: role)
      if reviews_published_at
        review.update!(deleted_at: Time.current)
        review.review&.destroy!
        refresh_circle_score!
      else
        review.destroy!
      end
      conversation_reviews.reset
    end
  end

  def publish_reviews!
    with_lock { publish_reviews_locked! }
  end

  def publish_reviews_locked!
    return if reviews_published_at || accepted_at.nil?
    return unless review_deadline <= Time.current || conversation_reviews.count == 2

    now = Time.current
    update!(reviews_published_at: now)
    conversation_reviews.each do |evaluation|
      evaluation.update!(published_at: now)
      next unless evaluation.author_role == 'member' && !evaluation.deleted_at
      Review.create!(user: user, member: member, review: evaluation.score, comment: evaluation.comment,
                     conversation_review: evaluation, nickname: member.nickname)
    end
    refresh_circle_score!
  end

  def refresh_circle_score!
    user.with_lock do
      user.review_score = user.reviews.average(:review).to_f * 5
      CircleScoreUpdater.new.refresh(user)
      user.save!
    end
  end
end
