module ReviewDeletionPermission
  def can_delete_review?(review)
    webmaster? ||
      (member_signed_in? && current_member.id == review.member_id) ||
      (review.conversation_review_id.nil? && admin_user_signed_in? &&
        current_admin_user.id == review.user.admin_user_id)
  end
end
