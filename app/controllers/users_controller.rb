class UsersController < ApplicationController
include ApplicationHelper
include Circlebook

before_action :authenticate_admin_user!, only: [:new, :create, :mypage, :edit, :update, :edit2, :update2, :edit3, :update3, :update_contact, :account_del]
before_action :ensure_correct_user, only: [:mypage, :edit, :update, :edit2, :update2, :edit3, :update3, :update_contact, :account_del]
before_action :require_master_account_for_destroy, only: [:destroy]
before_action :set_users, except: [:show, :new, :create]

helper_method :link_count


	def search
    # Userモデルオブジェクト作成
		@users = User

		# キーワード分割
    keywords = params[:q].split(/[[:blank:]]+/).select(&:present?)

		# 検索ワードの数だけand検索を行う
		keywords.each do |keyword|
			@event_ids = Event.where("name LIKE ?", "%#{keyword}%").pluck(:id)
			@prefecture_ids = Prefecture.where("name LIKE ?", "%#{keyword}%").pluck(:id)

			@city_ids = City.where("name LIKE ?", "%#{keyword}%").pluck(:id)
			@city_user_ids = UsersCity.where(city_id: @city_ids).pluck(:user_id)
			@tag_ids = Tag.where("name LIKE ?", "%#{keyword}%").pluck(:id)
			@tag_user_ids = UserTag.where(tag_id: @tag_ids).pluck(:user_id)

			@users = @users.search_word(keyword).
			or(@users.where(event_id: @event_ids)).
			or(@users.where(prefecture_id: @prefecture_ids)).or(@users.where(prefecture_sub_id: @prefecture_ids)).
			or(@users.where(id: @city_user_ids)).
			or(@users.where(id: @tag_user_ids))

		end

		# ソート機能
      if params[:sort] == "1" || params[:sort] == nil
      @users = @users.user_sort_1.page(params[:page])
      elsif params[:sort] == "2"
      @users = @users.user_sort_2.page(params[:page])
      else params[:sort] == "3"
      @users = @users.user_sort_3.page(params[:page])
      end

    # 検索ワードの保存

    # 各キーワードを半角で保存
    keywords.map.with_index(1){|kw,i|
      if i == 1
        @sort_kw = "#{@sort_kw}" + "#{kw}"
      else
        # 2個目以降は間に半角スペース
        @sort_kw = "#{@sort_kw}" + " #{kw}"
      end
    }
    if DbKeyword.find_by(keyword: @sort_kw) || params[:q].count("^ ") <= 1 || @users.count == 0
    else
      @db_keyword = DbKeyword.new
      @db_keyword.keyword = @sort_kw
      @db_keyword.save
    end

    # 既存と同じキーワードの場合カウント+1
    if @kw = DbKeyword.find_by(keyword: @sort_kw)
      @kw.increment!(:search_count, 1)
    end

		# パンくず
		@b1_name = "サークル検索"
    @b1_url = "/users"
    @b2_name = "「#{params[:q]}」の検索結果"
    @b2_url = ""
	end



	def new
    if admin_user_signed_in? #ログイン判定

      if current_admin_user.users.any?
        redirect_to "/users/#{current_admin_user.users.first.id}/mypage"
      else
        @user = User.new
        @admin_user = current_admin_user
      end

    else
      flash[:notice] = "登録が必要です"
      redirect_to root_path
    end
	end

	def add

    if admin_user_signed_in? #ログイン判定
      @ng_accounts = User.where(admin_user_id: current_admin_user.id, ng_account: "NG")
      if @ng_accounts.count == 0 && current_admin_user.users.count < 5
        @user = User.new
      else
        flash[:notice] = "URLが間違っています"
        redirect_to root_path
      end
    else
      flash[:notice] = "登録が必要です"
      redirect_to root_path
    end
	end


	def create
		@user = User.new(user_params)
		@user.admin_user_id = current_admin_user.id
		@user.last_post = Time.zone.now.ago(3.days)
		@user.user_time = Time.zone.now
    @user.switch = "募集中"

		if @user.save

      if @user.unique_id.blank?
        @user.unique_id = "#{@user.id}" + SecureRandom.alphanumeric(20)
      end

			# like検索用
			@user.grouping = @user.users_groups.includes(:group).map{|g| g.group.name}
			@user.average_age = @user.users_ages.includes(:age).map{|a| a.age.name}
			@user.save

			if @user.switch == "受付終了"
				@user.last_post = Time.zone.now.ago(60.days)
				@user.save
			end

			if @user.prefecture.id == 50 #全国選択

				@user.prefecture_sub_id = nil #サブエリアはnil
				@user.save

				flash[:notice] = 'ステップ１更新完了！'
				redirect_to circle_path(@user)

			else #47都道府県

				if @user.prefecture_id == @user.prefecture_sub_id #エリア重複判断
					@user.prefecture_sub_id = nil #サブエリアはnil
					@user.save
				end

				flash[:notice] = 'ステップ１更新完了！'
				redirect_to "/users/#{@user.id}/edit2"
			end

		else
			@admin_user = current_admin_user
			render "/users/edit"
		end

	end



	def edit
		@user = User.find(params[:id])
    @admin_user = @user.admin_user

		@user.users_ages.build
		@user.users_groups.build
		@user.users_cities.build
	end

	def edit2
		@user = User.find(params[:id])
		@prefecture = Prefecture.find(@user.prefecture_id)
		@cities = City.where(prefecture_id: @user.prefecture_id).order(:id => :asc)
		@sub_prefecture = Prefecture.find_by(id: @user.prefecture_sub_id)
		@sub_cities = City.where(prefecture_id: @user.prefecture_sub_id).order(:id => :asc)
		@user.users_cities.build

    if @user.link.present?
    else
      @user.build_link
    end

  end

	def edit3
    @user = User.find(params[:id])
    @admin_user = @user.admin_user
  end

  def admin_user_update
    @user = User.find(params[:id])
    @admin_user = @user.admin_user

		if admin_user_signed_in?
			if current_admin_user.master_account?
        @admin_user.update(admin_user_params)
        @admin_user.users.map{|user|
          user.last_post = Time.zone.now.ago(5.years)
          user.cb_point = -100
          user.save
        }

        flash[:notice] = '違反者登録完了！'
        redirect_to "/users/#{@user.id}"
			end
		end

  end


	def update
		@user = User.find(params[:id])
		@user.user_time = Time.zone.now unless current_admin_user.master_account?
    if @user.switch.nil?
      @user.switch = "募集中"
    end

		if @user.update(user_params)
			# like検索用
			@user.grouping = @user.users_groups.includes(:group).map{|g| g.group.name}
			@user.average_age = @user.users_ages.includes(:age).map{|a| a.age.name}
			@user.save
			if @user.switch == "受付終了"
				@user.last_post = Time.zone.now.ago(60.days)
				@user.save
			end
			if @user.prefecture.id == 50 #全国選択
				@user.prefecture_sub_id = nil #サブエリアはnil
				@user.save
				flash[:notice] = 'ステップ１更新完了！'
				redirect_to "/users/#{@user.id}/edit2"
			else #47都道府県
				if @user.prefecture_id == @user.prefecture_sub_id #エリア重複判断
					@user.prefecture_sub_id = nil #サブエリアはnil
					@user.save
				end
				flash[:notice] = 'ステップ１更新完了！'
				redirect_to "/users/#{@user.id}/edit2"
			end

		else
			render "/users/edit"
		end

	end

	def update2
		@user = User.find(params[:id])
		@prefecture = Prefecture.find(@user.prefecture_id)
		@cities = City.where(prefecture_id: @user.prefecture_id).order(:id => :asc)
		@sub_prefecture = Prefecture.find_by(id: @user.prefecture_sub_id)
		@sub_cities = City.where(prefecture_id: @user.prefecture_sub_id).order(:id => :asc)

    if @user.update(user_params)
      @user.id = @user.id
      @user.save
      flash[:notice] = 'ステップ２更新完了！'
      redirect_to "/users/#{@user.id}/edit3"
    else
      render "/users/edit2"
    end

	end

  def update3
		@user = User.find(params[:id])
    @admin_user = @user.admin_user
    if @admin_user.update(admin_user_params)

      flash[:notice] = 'プロフィール更新完了！'
      redirect_to circle_path(@user)
    else
      render "/users/edit3"
    end
  end


	def update_contact
		@user = User.find(params[:id])

		if @user.update(user_params)
			flash[:notice] = '「お問い合わせのテンプレ」更新完了！'
			redirect_to new_user_user_contact_path(@user)
		else
			flash[:notice] = 'URLを設定することはできません'
      redirect_to request.referer
		end
	end


	def destroy
		@user = User.find_by(id: params[:id])
    return redirect_to circles_path, notice: "該当するサークルが見つかりません" if @user.nil?

    # 削除データの保存
    @db_validation_error = DbValidationError.new
    @db_validation_error.name = "UserDelete" + "_#{@user.id}"
    @db_validation_error.content_01 = @user.name
    @db_validation_error.content_02 = @user.event.name
    @db_validation_error.content_03 = @user.prefecture.name
    @db_validation_error.save

		@user.destroy

		flash[:notice] = 'サークルを削除しました'
		redirect_to circles_path
	end

	def mypage
		@user = User.find(params[:id])
    @users = User.where.not(id: @user.id).where("cb_point > ?", 0).prefecture(@user.prefecture.id).event(@user.event.id).user_sort_2
    @questions_current = Question.where(user_id: @user.id)
    @questions_current_nil = Question.where(user_id: @user.id).where(answer: nil)
    @schedules = Schedule.where(user_id: @user.id).where("day > ?", DateTime.yesterday)
    @user_contacts = UserContact.where(user_id: @user.id, contact_del: nil)
    @user_contact_alerts = UserContact.where(user_id: @user.id, respond_check: "NG")

    @ng_accounts = User.where(admin_user_id: @user.admin_user_id, ng_account: "NG")
    @respond_check_count = UserContact.where(user_id: @user.id, respond_check: "NG").count
    cb_point(@user)

		# 管理者判定
		if admin_user_signed_in?

      # unique_id 付与
      if @user.unique_id.blank?
        @user.unique_id = "#{@user.id}" + SecureRandom.alphanumeric(20)
        if @user.save
        else
          flash[:notice] = '必須項目が設定されていません'
          redirect_to edit_user_path(@user)
        end
      end

			@blogs = Blog.where(user_id: @user.id).order(created_at: "DESC")
			@opinion = @user.opinions.build

      @blogs_imp = 0

			if @admin_user.users.any?
			else
				redirect_to "/user/add"
			end

		else
      flash[:notice] = "URLが管理者専用ページです"
      redirect_to circle_path(@user)
    end

    #無効メール
    if InvalidEmail.find_by(email: @user.admin_user.email)
      @invalid = "無効"
    else
      @invalid = "有効"
    end

		# パンくず
		@b1_name = @user.name
		@b1_url = "/users/#{@user.id}"
		@b2_name = "マイページ"
		@b2_url = "/users/#{@user.id}/mypage"
	end


	def login_form
	end

	def login
  end

  def logout
  end

	def update_email
		if admin_user_signed_in?
			@data = AdminUser.find_by(id: current_admin_user.id)
		end
	end


  def line
  end

  def admin_users
  end

	def prefecture_index
		# パンくず
		@b1_name = "47都道府県ごとのサークル"
		@b1_url = ""
	end



# 種目別ページ
	# def event
	# 	@event = Event.find_by(ruby: params[:ruby])
	# 	@prefectures = Prefecture.all.order(:order => :asc).where.not(kana: "nil")

	# 	# ソート機能
  #   if params[:sort] == "1" || params[:sort] == nil
  #     @users = User.event(@event.id).user_sort_1.page(params[:page])
  #   elsif params[:sort] == "2"
  #     @users = User.event(@event.id).user_sort_2.page(params[:page])
  #   else params[:sort] == "3"
  #     @users = User.event(@event.id).user_sort_3.page(params[:page])
  #   end

	# 	# パンくず
	# 	@b1_name = @event.name
  #   @b1_url = "/#{@event.ruby}"
	# end

	# def prefecture
	# 	@prefecture = Prefecture.find_by(kana: params[:kana])
	# 	@cities = City.where(prefecture_id: @prefecture.id).order(:id => :asc)

	# 	# ソート機能
  #     if params[:sort] == "1" || params[:sort] == nil
  #       @users = User.prefecture(@prefecture.id).or(User.prefecture_sub(@prefecture.id)).or(User.prefecture_50).pref.user_sort_1.page(params[:page])
  #     elsif params[:sort] == "2"
  #       @users = User.prefecture(@prefecture.id).or(User.prefecture_sub(@prefecture.id)).or(User.prefecture_50).pref.user_sort_2.page(params[:page])
  #     else params[:sort] == "3"
  #       @users = User.prefecture(@prefecture.id).or(User.prefecture_sub(@prefecture.id)).or(User.prefecture_50).pref.user_sort_3.page(params[:page])
  #     end

	# 	# パンくず
	# 	@b1_name = @prefecture.name
  #   @b1_url = "/prefectures/#{@prefecture.kana}"
	# end

	# def prefecture_city
	# 	@city = City.find_by(city_kana: params[:city_kana])
	# 	@prefecture =  Prefecture.find_by(id: @city.prefecture_id)
	# 	@cities = City.where(prefecture_id: @prefecture.id).order(:id => :asc)
	# 	@prefecture_judge = Prefecture.find_by(kana: params[:kana])

	# 	@city_users = @city.users_cities.pluck(:user_id)

	# 	# ソート機能
  #     if params[:sort] == "1" || params[:sort] == nil
  #       @users = User.city(@city_users).or(User.prefecture_50).pref.user_sort_1.page(params[:page])
  #     elsif params[:sort] == "2"
  #       @users = User.city(@city_users).or(User.prefecture_50).pref.user_sort_2.page(params[:page])
  #     else params[:sort] == "3"
  #       @users = User.city(@city_users).or(User.prefecture_50).pref.user_sort_3.page(params[:page])
  #     end

	# 	if @city.prefecture_id.to_i != @prefecture_judge.id.to_i
  #       flash[:notice] = "URLが間違っています"
  #       redirect_to circles_path
	# 	end

	# 	# パンくず
	# 	@b1_name = @prefecture.name
	# 	@b1_url = "/prefectures/#{@prefecture.kana}"
	# 	@b2_name = @city.name
  #   @b2_url = "/prefectures/#{@prefecture.kana}/#{@city.city_kana}"
	# end

	def prefecture_city_station
		@station = Station.find_by(id: params[:id])
    return redirect_to circles_path if @station.nil?
		@city = City.find_by(id: @station.city_id)

		@prefecture =  Prefecture.find_by(id: @city.prefecture_id)
		@cities = City.where(prefecture_id: @prefecture.id).order(:id => :asc)
		@prefecture_judge = Prefecture.find_by(kana: params[:kana])
		@city_judge = City.find_by(city_kana: params[:city_kana])

		@city_users = @city.users_cities.pluck(:user_id)

		# ソート機能
      if params[:sort] == "1" || params[:sort] == nil
        @users = User.city(@city_users).or(User.prefecture_50).pref.user_sort_1.page(params[:page])
      elsif params[:sort] == "2"
        @users = User.city(@city_users).or(User.prefecture_50).pref.user_sort_2.page(params[:page])
      else params[:sort] == "3"
        @users = User.city(@city_users).or(User.prefecture_50).pref.user_sort_3.page(params[:page])
      end

		if @city.prefecture_id.to_i != @prefecture_judge.id.to_i || @city.id.to_i != @city_judge.id.to_i
        flash[:notice] = "URLが間違っています"
        redirect_to circles_path
		end

		# パンくず
		@b1_name = @prefecture.name
		@b1_url = "/prefectures/#{@prefecture.kana}"
		@b2_name = @city.name
		@b2_url = "/prefectures/#{@prefecture.kana}/#{@city.city_kana}"
		@b3_name = @station.name
    @b3_url = "/prefectures/#{@prefecture.kana}/#{@city.city_kana}/#{@station.id}"
	end

	# def event_prefecture
	# 	@event = Event.find_by(ruby: params[:ruby])
	# 	@prefecture = Prefecture.find_by(kana: params[:kana])
	# 	@cities = City.where(prefecture_id: @prefecture.id).order(:id => :asc)

	# 	# ソート機能
  #     if params[:sort] == "1" || params[:sort] == nil
  #       @users = User.prefecture(@prefecture.id).or(User.prefecture_sub(@prefecture.id)).or(User.prefecture_50).event(@event.id).pref.user_sort_1.page(params[:page])
  #     elsif params[:sort] == "2"
  #       @users = User.prefecture(@prefecture.id).or(User.prefecture_sub(@prefecture.id)).or(User.prefecture_50).event(@event.id).pref.user_sort_2.page(params[:page])
  #     else params[:sort] == "3"
  #       @users = User.prefecture(@prefecture.id).or(User.prefecture_sub(@prefecture.id)).or(User.prefecture_50).event(@event.id).pref.user_sort_3.page(params[:page])
  #     end

	# 	# パンくず
	# 	@b1_name = @event.name
	# 	@b1_url = "/#{@event.ruby}"
	# 	@b2_name = @prefecture.name
  #   @b2_url = "/#{@event.ruby}/#{@prefecture.kana}"
	# end

	# def event_prefecture_city
	# 	@event = Event.find_by(ruby: params[:ruby])
	# 	@city = City.find_by(city_kana: params[:city_kana])
	# 	@prefecture =  Prefecture.find_by(kana: params[:kana])
	# 	@cities = City.where(prefecture_id: @prefecture.id).order(:id => :asc)
	# 	# @prefecture_judge = Prefecture.find_by(kana: params[:kana])

	# 	@city_users = @city.users_cities.pluck(:user_id)

	# 	# ソート機能
  #     if params[:sort] == "1" || params[:sort] == nil
  #       @users = User.city(@city_users).or(User.prefecture_50).event(@event.id).pref.user_sort_1.page(params[:page])
  #     elsif params[:sort] == "2"
  #       @users = User.city(@city_users).or(User.prefecture_50).event(@event.id).pref.user_sort_2.page(params[:page])
  #     else params[:sort] == "3"
  #       @users = User.city(@city_users).or(User.prefecture_50).event(@event.id).pref.user_sort_3.page(params[:page])
  #     end

	# 	# if @city.prefecture_id.to_i != @prefecture_judge.id.to_i
  #   #   flash[:notice] = "URLが間違っています"
  #   #   redirect_to circles_path
	# 	# end

	# 	# パンくず
	# 	@b1_name = @event.name
	# 	@b1_url = "/#{@event.ruby}"
	# 	@b2_name = @prefecture.name
	# 	@b2_url = "/#{@event.ruby}/#{@prefecture.kana}"
	# 	@b3_name = @city.name
  #   @b3_url = "/#{@event.ruby}/#{@prefecture.kana}/#{@city.city_kana}"
	# end


	def event_prefecture_city_station
		@event = Event.find_by(ruby: params[:ruby])
		@station = Station.find_by(id: params[:id])
    return redirect_to circles_path if @event.nil? || @station.nil?
		@city = City.find_by(id: @station.city_id)

		@prefecture =  Prefecture.find_by(id: @city.prefecture_id)
		@cities = City.where(prefecture_id: @prefecture.id).order(:id => :asc)
		@prefecture_judge = Prefecture.find_by(kana: params[:kana])
		@city_judge = City.find_by(city_kana: params[:city_kana])

		@city_users = @city.users_cities.pluck(:user_id)

		# ソート機能
    if params[:sort] == "1" || params[:sort] == nil
      @users = User.city(@city_users).or(User.prefecture_50).event(@event.id).pref.user_sort_1.page(params[:page])
    elsif params[:sort] == "2"
      @users = User.city(@city_users).or(User.prefecture_50).event(@event.id).pref.user_sort_2.page(params[:page])
    else params[:sort] == "3"
      @users = User.city(@city_users).or(User.prefecture_50).event(@event.id).pref.user_sort_3.page(params[:page])
    end

		if @city.prefecture_id.to_i != @prefecture_judge.id.to_i || @city.id.to_i != @city_judge.id.to_i
      flash[:notice] = "URLが間違っています"
      redirect_to circles_path
		end

		# パンくず
		@b1_name = @event.name
		@b1_url = "/#{@event.ruby}"
		@b2_name = @prefecture.name
		@b2_url = "/#{@event.ruby}/#{@prefecture.kana}"
		@b3_name = @city.name
		@b3_url = "/#{@event.ruby}/#{@prefecture.kana}/#{@city.city_kana}"
		@b4_name = @station.name
    @b4_url = "/#{@event.ruby}/#{@prefecture.kana}/#{@city.city_kana}/#{@station.id}"
	end

	def login
		@b1_name = "ログインページ"
		@b1_url = ""
  end


	def webmaster
    if current_admin_user.id == 1
    else
        flash[:notice] = "権限がありません"
        redirect_to circles_path
    end
	end

  def user_del
		if admin_user_signed_in?
      redirect_to "/users/#{current_admin_user.users.first.id}/account_del"
    else
      flash[:notice] = "ログインしてください"
      redirect_to new_admin_user_session_path
		end
  end

  def account_del
    @user = User.find(params[:id])

  end


def admin_user_list
  if admin_user_signed_in?
    if current_admin_user.id == 1
      @admin_users = AdminUser.last(100)
    else
      flash[:notice] = "権限がありません"
      redirect_to circles_path
    end
  end
end




private
	def set_users
		@search = User.ransack(params[:q])

		# ソート機能
    if params[:sort] == "1" || params[:sort] == nil
      @users = @search.result.user_sort_1.page(params[:page])
    elsif params[:sort] == "2"
      @users = User.user_sort_2.page(params[:page])
    else params[:sort] == "3"
      @users = User.user_sort_3.page(params[:page])
    end


    @categories = Category.all.order(:id => :asc)
		@events = Event.all.order(:order => :asc)
		@prefectures = Prefecture.all.order(:order => :asc)
		@cities = City.all.order(:id => :asc)
		@ages = Age.all
		@groups = Group.all.order(:id => :asc)
		@schedules = Schedule.where("day > ?", DateTime.yesterday).order(:day => :asc)
    @tags = Tag.all.order(:order => :asc)

    @search_word = "例）バスケ　東京"
		@category = "nil"
		@contact_judge = ""

		if admin_user_signed_in?
			@admin_user = current_admin_user
			@user = @admin_user.users.first
		end

	end

	def user_params
		params.require(:user).permit(
			:name, :email, :image_name, :header_image, :line_id, :switch, :item, :prefecture, :area, :schedule, :time_s, :time_e, :venue_address, :note, :age, :recruitment, :foundation, :member, :cost, :web, :appeal, :password, :goal, :user_id, :category_id, :event_id, :decade, :prefecture_id, :image, :pic_profile, :pic_header, :image_01, :image_02, :gallery_01, :gallery_02, :gallery_03, :gallery_04, :requirement, :impressions_count, :line_count, :mail_count, :user_time, :last_post, :contact, :twitter, :instagram, :txt, :prefecture_sub_id, :opinion, :template, :sent_count, :review_score, :ng_account, :unique_id,
      :remove_pic_profile, :remove_pic_header, :remove_gallery_01, :remove_gallery_02, :remove_gallery_03, :remove_gallery_04, :review_permit,
			decade_age:[], average_age:[] ,grouping:[], age_ids:[], group_ids:[], city_ids:[], tag_ids:[],
      link_attributes: [:id, :unique_id]
    )
	end

	def admin_user_params
		params.require(:admin_user).permit(:check, :gender, :nickname, :image_profile, :profile, :prefecture_id, :age, :open)
	end

	def ensure_correct_user
		if admin_user_signed_in?
			@user = User.find(params[:id])

			if current_admin_user.id == @user.admin_user_id
				# OK
			elsif current_admin_user.master_account?
				#OK
			else
        flash[:notice] = "権限がありません"
        redirect_to circles_path
			end

		end
	end

  def require_master_account_for_destroy
    unless admin_user_signed_in? && current_admin_user.master_account?
      flash[:notice] = "権限がありません"
      redirect_to circles_path
    end
  end

  def set_unique_id
    # id未設定、または、すでに同じunique_idのレコードが存在する場合はループに入る
    while @user.unique_id.blank? || User.find_by(unique_id: @user.unique_id).present? do
      # ランダムな20文字をunique_idに設定し、whileの条件検証に戻る
      @user.unique_id = SecureRandom.alphanumeric(20)
    end
    @user.save
  end



end
