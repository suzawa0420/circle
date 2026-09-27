class Blogs::BlogsController < Blogs::ApplicationController

  before_action :set_search, only: [:index]

	def index
		admin_user_ids = AdminUser.publicly_visible.select(:id)
    user_ids = User.where(admin_user_id: admin_user_ids).users_list.select(:id)
    @blogs = Blog.list(user_ids).page(params[:page])
  end

end
