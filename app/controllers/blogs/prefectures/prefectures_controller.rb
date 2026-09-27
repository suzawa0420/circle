class Blogs::Prefectures::PrefecturesController < Blogs::Prefectures::ApplicationController
  before_action :set_search, only: [:show]

	def index
    redirect_to blogs_path, status: 301
  end


  def show
		@prefecture = Prefecture.find_by(kana: params[:kana])
    admin_user_ids = AdminUser.publicly_visible.pluck(:id)

    user_ids = User.where(admin_user_id: admin_user_ids).where_pref(@prefecture.id).users_list.pluck(:id)
    @blogs = Blog.list(user_ids).page(params[:page])


  end

end
