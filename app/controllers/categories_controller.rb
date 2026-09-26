class CategoriesController < ApplicationController

  before_action :set_users

  #noindex
  def index
    @users = User.user_sort_1.page(params[:page])
    @prefectures = Prefecture.all.order(:order => :asc)
    @categories = Category.all.order(:order => :asc)

		# パンくず
		@b1_name = "カテゴリー"
		@b1_url = ""
  end

  #noindex
  def prefecture_index
    @users = User.user_sort_1.page(params[:page])
    @prefectures = Prefecture.all.order(:order => :asc)
    @categories = Category.all.order(:order => :asc)

		# パンくず
		@b1_name = "カテゴリー"
		@b1_url = ""
  end

  #noindex
  def prefecture
    @categories = Category.all.order(:order => :asc)
    @prefecture = Prefecture.find_by(kana: params[:kana])
    @users = User.prefecture(@prefecture.id).or(User.prefecture_sub(@prefecture.id)).or(User.prefecture_50).publicly_visible.pref.user_sort_1.page(params[:page])

		# パンくず
		@b1_name = "カテゴリー"
		@b1_url = "/categories"
		@b2_name = @prefecture.name
		@b2_url = ""
  end

  def category
    @category = Category.find_by(kana: params[:kana])
    @events = Event.where(category_id: @category.id).order(:order => :asc)
    @prefectures = Prefecture.all.order(:order => :asc)
    @users = User.event(@events).publicly_visible.pref.user_sort_1.page(params[:page])

		# パンくず
		@b1_name = "カテゴリー"
		@b1_url = "/categories"
		@b2_name = @category.name
		@b2_url = ""
  end

  def category_prefecture
    @category = Category.find_by(kana: params[:kana])
    @events = Event.where(category_id: @category.id).order(:order => :asc)
    @prefecture = Prefecture.find_by(kana: params[:p_kana])
    @users = User.prefecture(@prefecture.id).or(User.prefecture_sub(@prefecture.id)).or(User.prefecture_50).event(@events).publicly_visible.pref.user_sort_1.page(params[:page])

		# パンくず
		@b1_name = "カテゴリー"
		@b1_url = "/categories"
		@b2_name = @category.name
		@b2_url = "/categories/#{@category.name}"
		@b3_name = @prefecture.name
		@b3_url = ""
  end


private
	def set_users

    @search_word = "例）バスケ　東京"
		@contact_judge = ""

		if admin_user_signed_in?
			@admin_user = current_admin_user
			@user = @admin_user.users.first
		end

	end



end

