class LinksController < ApplicationController


# before_action :ensure_correct_user, {only: [:edit, :update]}
# before_action :set_links


	def index
		@links = Link.where(user_id: User.publicly_visible.select(:id)).where.not(link03_title: "").order("RANDOM()").limit(5)
	end

	def new
		@user = User.find(params[:user_id])
		@links = Link.where(user_id: User.publicly_visible.select(:id)).where.not(link03_title: "").order("RANDOM()").limit(5)

		if admin_user_signed_in?
			if current_admin_user.id == @user.admin_user_id.to_i
				if @user.link.present?
					@link = @user.link
					redirect_to "/link/#{@link.unique_id}"
				else
					@link = Link.new
				end
			else
				flash[:notice] = "権限がありません"
        redirect_to links_path
			end

    else
      flash[:notice] = "ログインをしてください"
      redirect_to "/admin_users/sign_in"
		end

		# パンくず
		@b2_name = "サークルリンク"
		@b2_url = "/links"
		@b3_name = @user.name
		@b3_url = "/users/#{@user.id}"
		@b4_name = "新規作成"
		@b4_url = ""

	end

	def create
		@link = Link.new(link_params)
		@user = User.find(params[:user_id])
    @links = Link.where.not(link03_title: "").order("RANDOM()").limit(5)
		@link.user_id = @user.id
		@link.link01_title = @user.name
		@link.link01_url = "https://circle-book.com/users/#{@user.id}"

		if @user.match.present?
			if @user.match.recruit = "募集中"
				@link.link02_title = "対戦相手の募集ページ"
				@link.link02_url = "https://circle-book.com/matches/#{@user.id}"
			end
		end

		if @link.save(link_params)
			flash[:notice] = 'ID設定完了しました！'
			redirect_to "/link/#{@link.unique_id}"
		else
			render "new"
		end

	end

	def show
		@link = Link.find(params[:id])
		@user = @link.user
		raise ActiveRecord::RecordNotFound unless @user.publicly_visible? || (admin_user_signed_in? && (current_admin_user.master_account? || current_admin_user.id == @user.admin_user_id))
		@sub_prefecture = Prefecture.find_by(id: @user.prefecture_sub_id)

	end

	def link

		@link = Link.find_by(unique_id: params[:unique_id])

		if @link.nil?
			flash[:notice] = "URLが間違っています"
      redirect_to links_path

		else
			@user = @link.user
			raise ActiveRecord::RecordNotFound unless @user.publicly_visible? || (admin_user_signed_in? && (current_admin_user.master_account? || current_admin_user.id == @user.admin_user_id))
			@sub_prefecture = Prefecture.find_by(id: @user.prefecture_sub_id)

			# パンくず
			@b2_name = "サークルリンク"
			@b2_url = "/links"
			@b3_name = @user.name
			@b3_url = "/users/#{@user.id}"
			@b4_name = "リンク集"
			@b4_url = ""

		end


	end

  def unique_page
    if @link = Link.find_by(unique_id: params[:unique_id])
      @user = @link.user
      redirect_to circle_path(@user.id)
    else
			flash[:notice] = "URLが間違っています"
      redirect_to circles_path
    end
  end


	def edit
		@link = Link.find(params[:id])
		@user = @link.user

		if admin_user_signed_in?

			if current_admin_user.id != @link.user.admin_user_id.to_i
				if current_admin_user.id == 1
        else
          flash[:notice] = "権限がありません"
          redirect_to links_path
        end
			end

		else
      flash[:notice] = "権限がありません"
      redirect_to links_path
		end

		# パンくず
		@b2_name = "サークルリンク"
		@b2_url = "/links"
		@b3_name = @user.name
		@b3_url = "/users/#{@user.id}"
		@b4_name = "リンク集"
		@b4_url = "/link/#{@link.unique_id}"
	end

	def update
		@link = Link.find(params[:id])
		if @link.update(link_params)
			flash[:notice] = '更新完了！'
			redirect_to "/link/#{@link.unique_id}"
		else
			flash[:notice] = '入力エラー'
			render "edit"
		end
	end

	def destroy

	end

private
	def link_params
		params.require(:link).permit(
			:unique_id, :link01_title, :link01_url, :link02_title, :link02_url, :link03_title, :link03_url, :link04_title, :link04_url, :link05_title, :link05_url
    )
	end

	def set_linkes
	end

	def ensure_correct_user
	end


end
