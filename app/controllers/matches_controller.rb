class MatchesController < ApplicationController

before_action :ensure_correct_user, {only: [:edit, :update]}
before_action :set_matches


	def index
		@matches = matches_with_user_details.order(updated_at: :desc).page(params[:page])
	end

	def new
		@user = User.find(params[:user_id])

    if admin_user_signed_in? #ログイン判定

      if @user.match.blank? #未登録
        if params[:count] == "new"
          flash[:notice] = "必要情報を登録してください"
        end
        @match = Match.new

        if @user.event.matching == 0
            flash[:notice] = "#{@user.event.name}は登録できません"
            redirect_to root_path
        end

      else #登録済み
        redirect_to edit_match_path(@user.id)
      end

    else
      flash[:notice] = "登録が必要です"
      redirect_to root_path
    end

	end

	def create
		@match = Match.new(match_params)
		@user = User.find(params[:user_id])
		@match.id = @user.id
		@match.user_id = @user.id
		@match.recruit = "募集中"
		@match.save

		if @match.update(match_params)
			flash[:notice] = '登録完了！'
			redirect_to match_path(@match.id)
		else
			render "edit"
		end


	end

	def show
		@user = User.includes(:event, :prefecture, :prefecture_sub).find(params[:id])
		@match = Match.find_by(user_id: @user.id)
		@event = @user.event
		@prefecture = @user.prefecture
		@sub_prefecture = @user.prefecture_sub

		user_ids = User.where(event_id: @event.id, prefecture_id: @prefecture.id).select(:id)
		@matches = matches_with_user_details.where(user_id: user_ids).where.not(id: @match.id).order(updated_at: :desc)



		# パンくず
		@b2_name = @event.name
		@b2_url = "/match/#{@event.ruby}"
		@b3_name = @prefecture.name
		@b3_url = "/match/#{@event.ruby}/#{@prefecture.kana}"
		@b4_name = @match.user.name
		@b4_url = ""
	end

	def edit
	end

	def update
		if @match.update(match_params)
			flash[:notice] = '更新完了！'
			redirect_to match_path(@match.id)
		else
			render "edit"
		end	
	end

	def destroy
	end

	def match
		redirect_to matches_path
	end


	def event
		@event = Event.find_by(ruby: params[:ruby])
		user_ids = User.where(event_id: @event.id).select(:id)

		@matches = matches_with_user_details.where(user_id: user_ids).order(updated_at: :desc).page(params[:page])
 
		# パンくず
		@b2_name = @event.name
		@b2_url = "/match/#{@event.ruby}"
	end

	def prefecture
		@prefecture = Prefecture.find_by(kana: params[:kana])
		user_ids = User.where(prefecture_id: @prefecture.id).select(:id)
		@matches = matches_with_user_details.where(user_id: user_ids).order(updated_at: :desc).page(params[:page])

		# パンくず
		@b2_name = @prefecture.name
		@b2_url = "/match/prefectures/#{@prefecture.kana}"
	end

	def event_prefecture
		@event = Event.find_by(ruby: params[:ruby])
		@prefecture = Prefecture.find_by(kana: params[:kana])
		user_ids = User.where(event_id: @event.id, prefecture_id: @prefecture.id).select(:id)
		@matches = matches_with_user_details.where(user_id: user_ids).order(updated_at: :desc).page(params[:page])

		# パンくず
		@b2_name = @event.name
		@b2_url = "/match/#{@event.ruby}"
		@b3_name = @prefecture.name
		@b3_url = "/match/#{@event.ruby}/#{@prefecture.kana}"
	end

private
	def matches_with_user_details
		Match.includes(user: [:event, :prefecture])
	end

	def match_params
		params.require(:match).permit(
			:age_group, :member, :level, :recruit, :comment
    )
	end

	def set_matches
		@events = Event.all.where.not(id: 0,matching: 0).order(:order => :asc)
		@prefectures = Prefecture.all.order(:order => :asc).where.not(id: 0)

		if admin_user_signed_in?
			@current_user = User.find_by(id: current_admin_user.id)
			@current_match = Match.find_by(id: current_admin_user.id)
		end

		# パンくず
		@b1_name = "対戦相手・練習試合の募集"
		@b1_url = "/matches"
	end

	def ensure_correct_user
		@match = Match.find(params[:id])
    if current_admin_user.id != @match.user.admin_user_id.to_i
      if current_admin_user.id == 1
      else
        flash[:notice] = "権限がありません"
        redirect_to matches_path
      end
    end
	end



end
