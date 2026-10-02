module Circlebook
  extend ActiveSupport::Concern

    # サークルブックポイント（サクブポイント）
    def cb_point(user)
      @schedule_point = user.schedules.count * 0.1
      @blog_point = user.blogs.count * 0.2
      @qa_point = Question.where(user_id: user.id).where.not(answer: nil).count * 0.3
      @review_point = Review.where(user_id: user.id, review: 1).count * 2
      # @contact_point = UserContact.where(user_id: user.id, contact_del: nil).count * 0.5
      @respond_point = (UserContact.where(user_id: user.id, respond_check: "NG").count + Conversation.where(user_id: user.id, respond_check: "NG").count) * 30

      if user.admin_user.check.present? && user.admin_user.check != 0
        # 違反者
        user.cb_point = -100
      elsif user.user_time.blank?
        user.cb_point = 0
      elsif user.user_time.to_time <= Time.zone.now.ago(1.years)
        user.cb_point = 0
      else
        # user.cb_point = @blog_point + @schedule_point + @qa_point + @review_point + @contact_point - @respond_point
        user.cb_point = @blog_point + @schedule_point + @qa_point + @review_point - @respond_point
      end

    end

    # ソート用の日付更新
    def last_post(user)
			@user.user_time = Time.zone.now
      if user.admin_user.check.present? && user.admin_user.check != 0
        # 違反者
        @user.last_post = Time.zone.now.ago(5.years)
      else
        @user.last_post = Time.zone.now
      end
    end



end