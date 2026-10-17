class Conversation < ApplicationRecord
  class NotAllowed < StandardError; end
  # Keep this switch to pause new practice inquiries without losing existing history.
  PRACTICE_MATCH_ENABLED = true

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

  NO_REPLY_WAIT = 3.days
  scope :reported_unanswered, -> {
    delivered_inquiries = ChatMessage.deliverable.where(sender_role: 'member')
      .where('COALESCE(chat_messages.released_at, chat_messages.created_at) <= ?', NO_REPLY_WAIT.ago)
      .select(:conversation_id)
    where(source_user_id: nil, respond_check: 'NG', accepted_at: nil, id: delivered_inquiries)
  }

  def no_reply_reportable_at
    first_inquiry = chat_messages.deliverable.where(sender_role: 'member')
      .order(Arel.sql('COALESCE(chat_messages.released_at, chat_messages.created_at) ASC, id ASC')).first
    (first_inquiry.released_at || first_inquiry.created_at) + NO_REPLY_WAIT if first_inquiry
  end

  ROLES = %w[member owner].freeze
  belongs_to :user
  belongs_to :member, optional: true
  belongs_to :source_user, class_name: 'User', optional: true
  validates :member, presence: true, unless: :practice_match?
  validate :valid_circle_participants
  has_many :chat_messages, dependent: :destroy
  has_many :conversation_reviews, dependent: :destroy
  has_many :chat_reports, dependent: :destroy
  has_many :conversation_reply_reports, dependent: :destroy
  has_many :no_show_reports, dependent: :destroy

  def unanswered_message_for(role)
    raise NotAllowed, 'この操作はできません。' unless ROLES.include?(role) && !practice_match?
    peer = role == 'member' ? 'owner' : 'member'
    last_reply = chat_messages.deliverable.where(sender_role: peer).delivery_order.first
    outgoing = chat_messages.deliverable.where(sender_role: role)
    if last_reply
      delivered_at = last_reply.released_at || last_reply.created_at
      outgoing = outgoing.where('(COALESCE(released_at, created_at), id) > (?, ?)', delivered_at, last_reply.id)
    end
    outgoing.reorder(Arel.sql('COALESCE(released_at, created_at) ASC'), id: :asc).first
  end

  def reply_reportable_at(role)
    message = unanswered_message_for(role)
    (message.released_at || message.created_at) + NO_REPLY_WAIT if message
  end

  def no_reply_reported_by?(role)
    return true if role == 'member' && self.class.reported_unanswered.exists?(id)
    conversation_reply_reports.active.where(reporter_role: role).exists?
  end

  def report_no_reply!(role)
    with_lock do
      ensure_active_sender!(role)
      raise NotAllowed, 'メールアドレスを確認してください。' unless actor(role).email_verified?
      raise NotAllowed, '送信停止中の会話は未返信として報告できません。' if blocked?
      message = unanswered_message_for(role)
      raise NotAllowed, '返信待ちの配信済みメッセージがありません。' unless message
      if (message.released_at || message.created_at) + NO_REPLY_WAIT > Time.current
        raise NotAllowed, 'やり取りの中で、自分のメッセージに3日以上返信がない場合に報告できます。'
      end
      report = conversation_reply_reports.find_or_initialize_by(reporter_role: role)
      report.update!(chat_message: message)
      if role == 'member' && !accepted_at
        update!(respond_check: 'NG')
        refresh_circle_score!
      end
    end
  end

  def self.for_member!(user, member)
    raise NotAllowed, '利用停止中のため、新しい問い合わせはできません。' if member.reload.suspended? || user.admin_user.reload.suspended?
    create_or_find_by!(user: user, member: member) do |conversation|
      conversation.legacy_member_review = Review.exists?(user: user, member: member)
    end
  end

  # Stored member/owner roles describe the two sides; for practice matches both are organizers.
  def practice_match? = source_user_id.present?
  def person(role) = role == 'owner' ? user : (practice_match? ? source_user : member)
  def actor(role) = person(role).is_a?(User) ? person(role).admin_user : person(role)
  def participant_name(role) = person(role).is_a?(User) ? person(role).name : person(role).nickname

  scope :for_owner, ->(owner) {
    ids = owner.users.select(:id)
    where(user_id: ids).or(where(source_user_id: ids))
  }

  def role_for(member_account, owner_account)
    return 'member' if practice_match? && owner_account && source_user.admin_user_id == owner_account.id
    return 'member' if !practice_match? && member_account && member_id == member_account.id
    'owner'
  end

  def self.for_circles!(target, source)
    raise NotAllowed, '練習試合のメッセージ機能を準備しています。少し待ってからお試しください。' unless PRACTICE_MATCH_ENABLED
    pair = where(user: target, source_user: source).or(where(user: source, source_user: target))
    pair.first || transaction(requires_new: true) { create!(user: target, source_user: source) }
  rescue ActiveRecord::RecordNotUnique
    pair.first!
  end

  def valid_circle_participants
    return unless practice_match?
    errors.add(:base, 'ご自身のサークルには問い合わせできません。') if user&.admin_user_id == source_user&.admin_user_id
    errors.add(:member, 'は指定できません。') if member_id.present?
  end

  def ensure_active_sender!(role)
    raise NotAllowed, '送信者が不正です。' unless ROLES.include?(role)
    sender = actor(role)
    raise NotAllowed, '利用停止中はメッセージ・口コミを投稿できません。' if sender.reload.suspended?
  end

  def blocked?
    member_blocked? || owner_blocked?
  end

  # Serialize initial inquiries across different circles for the same sender.
  def send_message!(role, body, image: nil, inquiry_context: nil)
    if role == 'member'
      actor(role).with_lock { send_message_locked!(role, body, image: image, inquiry_context: inquiry_context) }
    else
      send_message_locked!(role, body, image: image, inquiry_context: inquiry_context)
    end
  end

  def send_message_locked!(role, body, image: nil, inquiry_context: nil)
    with_lock do
      raise NotAllowed, 'ブロック中はメッセージを送信できません。' if blocked?
      ensure_active_sender!(role)
      if !practice_match? && role == 'member' && !member.japanese_profile?
        raise NotAllowed, '自己紹介を日本語（ひらがな・カタカナを含む文章）に修正してから送信してください。'
      end
      sender = actor(role)
      raise NotAllowed, 'メールアドレスを確認してください。' unless sender.email_verified?
      if chat_messages.where(sender_role: role).where('created_at > ?', 1.minute.ago).count >= 10
        raise NotAllowed, '送信が続いています。少し待ってからお試しください。'
      end
      if !practice_match? && role == 'owner' && !chat_messages.deliverable.where(sender_role: 'member').exists?
        raise NotAllowed, '参加者からの問い合わせを受けてから返信できます。'
      end
      if !practice_match? && role == 'member' && !chat_messages.exists?
        CircleInquiryGuidance.new(user).messages.each do |guidance|
          chat_messages.create!(sender_role: 'system', body: guidance)
        end
      end
      attributes = { sender_role: role, body: body.to_s, image: image }
      attributes[:inquiry_context] = inquiry_context if role == 'member' && !practice_match? && inquiry_context.present?
      if role == 'member' && accepted_at.nil?
        result = ChatSpamDetector.evaluate(self, body)
        attributes.merge!(spam_score: result.score, spam_reasons: result.reasons, spam_fingerprint: result.fingerprint,
                          moderation_status: result.held? ? 'held' : 'delivered')
      end
      message = chat_messages.create!(attributes)
      return message unless message.delivered?
      if !practice_match? && role == 'owner' && accepted_at.nil?
        self.accepted_at = Time.current
        self.review_deadline = 30.days.from_now
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

  private :send_message_locked!

  def recipient_read_message_id(sender_role)
    self[sender_role == 'owner' ? 'member_read_message_id' : 'owner_read_message_id']
  end

  def message_read?(message)
    return false if message.automatic? || message.conversation_id != id || !message.delivered?
    message.released_at ? message.recipient_read_at.present? : message.id <= recipient_read_message_id(message.sender_role)
  end

  def mark_read!(role, through:, message_ids: [])
    with_lock do
      self["#{role}_read_message_id"] = [self["#{role}_read_message_id"], through].max
      incoming_role = role == 'member' ? 'owner' : 'member'
      chat_messages.deliverable.where(id: message_ids, sender_role: incoming_role, recipient_read_at: nil)
        .where.not(released_at: nil).update_all(recipient_read_at: Time.current)
      unless chat_messages.unread_by(role, self["#{role}_read_message_id"]).exists?
        self["#{role}_notification_due_at"] = nil
      end
      update_columns("#{role}_read_message_id" => self["#{role}_read_message_id"],
                     "#{role}_notification_due_at" => self["#{role}_notification_due_at"])
    end
  end

  # Each side controls its own reminders; peer scores and comments stay private.
  def review_writable?(role)
    return false unless ROLES.include?(role)
    return false if practice_match? || accepted_at.nil? || review_deadline.nil?
    return false if reviews_published_at || review_deadline <= Time.current
    return false if actor(role).suspended? || !actor(role).email_verified?
    return false if role == 'member' && (legacy_member_review? || Review.exists?(user: user, member: member))

    true
  end

  def review_prompt_due?(role)
    return false unless review_writable?(role)
    return false if self["#{role}_review_prompt_dismissed"]
    return false if conversation_reviews.any? { |review| review.author_role == role }

    (self["#{role}_review_prompt_after"] || accepted_at + 7.days) <= Time.current
  end

  def peer_review_waiting?(role)
    return false unless review_writable?(role)
    reviews = conversation_reviews.to_a
    reviews.none? { |review| review.author_role == role } &&
      reviews.any? { |review| review.author_role != role && !review.deleted_at && !review.published_at }
  end

  def invite_peer_reviewer!(author_role)
    recipient = author_role == 'member' ? 'owner' : 'member'
    return if self["#{recipient}_review_invited_at"] || !peer_review_waiting?(recipient)

    update!("#{recipient}_review_invited_at" => Time.current,
            "#{recipient}_review_notification_due_at" => 5.minutes.from_now,
            "#{recipient}_review_prompt_after" => Time.current)
  end

  def update_review_prompt!(role, choice)
    raise NotAllowed, '案内の設定が不正です。' unless ROLES.include?(role) && %w[later dismiss].include?(choice)

    with_lock do
      raise NotAllowed, '口コミの案内対象外です。' unless review_prompt_due?(role)

      if choice == 'later'
        update!("#{role}_review_prompt_after" => 7.days.from_now)
      else
        update!("#{role}_review_prompt_dismissed" => true)
      end
    end
  end

  def submit_review!(role, attributes)
    raise NotAllowed, '練習試合の相談は口コミの対象外です。' if practice_match?
    with_lock do
      ensure_active_sender!(role)
      publish_reviews_locked!
      raise NotAllowed, '評価の投稿期間外です。' unless accepted_at && review_deadline > Time.current && reviews_published_at.nil?
      if role == 'member' && (legacy_member_review? || Review.exists?(user: user, member: member))
        raise NotAllowed, 'このサークルへの評価はすでに投稿済みです。'
      end
      review = conversation_reviews.find_or_initialize_by(author_role: role)
      raise NotAllowed, '公開後の評価は編集・再投稿できません。' if review.published_at || review.deleted_at
      new_submission = review.new_record?
      review.assign_attributes(attributes)
      review.participated = false if role == 'owner'
      review.save!
      unless first_review_submitted_at
        self.first_review_submitted_at = review.created_at
        self.review_deadline = first_review_submitted_at + 14.days
        save!
      end
      conversation_reviews.reset
      publish_reviews_locked!
      invite_peer_reviewer!(role) if new_submission
      review
    end
  end

  def delete_review!(role)
    raise NotAllowed, '練習試合の相談は口コミの対象外です。' if practice_match?
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
    return if practice_match? || reviews_published_at || accepted_at.nil?
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
