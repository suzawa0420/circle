class Circles::BlogsController < Circles::ApplicationController

  before_action :authenticate_admin_user!, except: [:index, :show]
  before_action :set_blog
  before_action :authorize_blog_write, only: [:new, :create, :edit, :update, :destroy]
  before_action :security_blog, only: [:edit, :update, :destroy]
  before_action :protect_submission, only: [:create, :update]

  include Circlebook

  def index
    @blogs = @user.blogs.order(created_at: "DESC").page(params[:page])
  end


	def new
    @blog = Blog.new
  end


	def create
    @blog = Blog.new(blog_params)
		@blog.user_id = @user.id

		if @blog.save
      last_post(@user)
      cb_point(@user)
      @user.save

			flash[:notice] = 'ブログ投稿完了！'
			redirect_to circle_blog_path(@user, @blog)
		else
			render "new"
		end
	end


	def show
		@blog = Blog.find(params[:id])
    @blogs = @user.blogs.where.not(id: params[:id])

    if @user.blogs.exists?(id: @blog.id)

    else
			flash[:notice] = 'URLが間違っています'
			redirect_to blogs_path
    end
	end


	def edit
    @blog = Blog.find(params[:id])
  end

	def update
		@blog = Blog.find(params[:id])

		if @blog.update(blog_params)

			@user.user_time = Time.zone.now
      @user.save
			flash[:notice] = 'ブログ更新完了！'
			redirect_to circle_blog_path(@blog.user.id, @blog.id)
		else
			render "edit"
		end
	end


	def destroy
    @blog = Blog.find_by(id: params[:id])
    @blog.destroy
    cb_point(@blog.user)
    @blog.user.save

		flash[:notice] = 'ブログ削除完了'
		redirect_to circle_path(@user.id)
	end


  private
  def blog_params
    params.require(:blog).permit(
      :title,
      :content,
      :image_01,
      :image_02,
      :image_03,
      :image_04,
      :remove_image_01, :remove_image_02, :remove_image_03, :remove_image_04,
      :image_name,
      :name,
      :requirement,
      :impressions_count
    )
  end

  def set_blog
    @user = User.find(params[:circle_id])
  end


  def authorize_blog_write
    allowed = current_admin_user.master_account? || (
      @user.admin_user_id == current_admin_user.id &&
      [nil, 0].include?(current_admin_user.check) &&
      !current_admin_user.users.exists?(ng_account: 'NG')
    )
    render plain: '現在、このサークルのブログは投稿・編集できません。', status: :forbidden unless allowed
  end

  def security_blog
    @user.blogs.find(params[:id])
  end

  def protect_submission
    verify_spam_form!("blog:#{@user.id}")
  end
end
