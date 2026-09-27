class Blogs::Events::PrefecturesController < Blogs::Events::ApplicationController
  before_action :set_search, only: [:show]

	def index
    redirect_to blogs_event_path(params[:event_kana]), status: 301
  end

  def show
		@event = Event.find_by(ruby: params[:event_kana])
		@prefecture = Prefecture.find_by(kana: params[:kana])
    admin_user_ids = AdminUser.publicly_visible.pluck(:id)

    user_ids = User.where(admin_user_id: admin_user_ids).where(event_id: @event.id).where_pref(@prefecture.id).users_list.pluck(:id)
    @blogs = Blog.list(user_ids).page(params[:page])

  end


end
