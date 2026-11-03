# Apply before pagination/limits so flagged organizers cannot occupy the first page.
module PublicListingOrder
  extend ActiveSupport::Concern

  included do
    scope :moderation_last, -> {
      priority = Arel.sql("CASE WHEN #{moderation_order_predicate} THEN 1 ELSE 0 END ASC")
      reorder(priority, *order_values)
    }
  end

  class_methods do
    def moderation_order_predicate
      flagged_owners = AdminUser.where(check: [1, 2, 3]).select(:id)
      if table_name == 'users'
        "users.admin_user_id IN (#{flagged_owners.to_sql})"
      else
        flagged_circles = User.where(admin_user_id: flagged_owners).select(:id)
        "#{table_name}.user_id IN (#{flagged_circles.to_sql})"
      end
    end
  end
end
