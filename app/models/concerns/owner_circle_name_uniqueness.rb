module OwnerCircleNameUniqueness
  extend ActiveSupport::Concern

  included do
    validate :circle_name_not_used_by_owner, if: :owner_circle_name_changing?
    before_save :serialize_owner_circle_name, if: :owner_circle_name_changing?
  end

  private

  def owner_circle_name_changing?
    admin_user_id.present? && name.present? &&
      (new_record? || will_save_change_to_name? || will_save_change_to_admin_user_id?)
  end

  def circle_name_key(value)
    # Compare surrounding whitespace only. Preserve the entered display name,
    # internal spaces, case and character width used by existing listings.
    value.to_s.gsub(/\A[[:space:]]+|[[:space:]]+\z/, '')
  end

  def circle_name_not_used_by_owner
    siblings = self.class.where(admin_user_id: admin_user_id)
    siblings = siblings.where.not(id: id) if persisted?
    if siblings.pluck(:name).any? { |other| circle_name_key(other) == circle_name_key(name) }
      errors.add(:name, 'は同じアカウントですでに登録されています。登録済みのサークルを編集するか、別の名前を入力してください。')
    end
  end

  def serialize_owner_circle_name
    # save/save! already wrap callbacks and the INSERT/UPDATE in a transaction.
    # Keep the account row lock until commit, then recheck after any concurrent
    # writer. A validation alone would let two simultaneous requests both pass.
    # Unlike a unique index, this retains legacy duplicates and allows unrelated
    # edits to those records. Also enforce this check for save(validate: false).
    AdminUser.where(id: admin_user_id).lock('FOR NO KEY UPDATE').pick(:id)
    circle_name_not_used_by_owner
    throw(:abort) if errors[:name].any?
  end
end
