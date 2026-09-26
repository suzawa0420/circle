class MembersController < ApplicationController

    before_action :authenticate_member!, only: [:edit, :update, :show]
    before_action :ensure_correct_member, {only: [:edit, :update, :show]}
	before_action :set_member

	def index
        redirect_to circles_path
	end

	def create

	end

    def edit
        @member = Member.find(params[:id])
        @events = Event.all.order(order: :asc)
        @prefectures = Prefecture.where.not(id: 50).order(:order => :asc)
    end

    def update
        @member = Member.find(params[:id])

        if @member.random_id.nil?
            @member.random_id = SecureRandom.alphanumeric(6)
        end

        if @member.update(member_params)

            flash[:notice] = 'プロフィール更新完了！'
            redirect_to circles_path
        else
            render "edit"
        end
    end

    def show
        @member = Member.find(params[:id])
        @event_answers = EventAnswer.where(member_id: @member.id)
        @events = Event.all

        @event_ids = @member.members_events.map { |e| e.event_id }
        @r_users = User.where(prefecture_id: @member.prefecture_id).or(User.where(prefecture_sub_id: @member.prefecture_id)).publicly_visible.where(event_id: @event_ids).order("RANDOM()").limit(5)

        @bookmarks = Bookmark.where(member_id: @member.id).map { |m| m.user_id }
        @b_users = User.publicly_visible.where(id: @bookmarks)

        @event_questions = EventQuestion.all


        # パンくず
        @b1_name = @member.nickname
        @b1_url = ""
    end

    def ensure_correct_member
      if current_member.id != params[:id].to_i
        if current_member.id == 1

        else
          flash[:notice] = "権限がありません"
          redirect_to circles_path

        end
      end
    end


    def set_member
      @event = Event.find_by(ruby: params[:ruby])
      @event_question = EventQuestion.find_by(id: params[:id])
    end


    private

    def member_params
        params.require(:member).permit(
            :id,
            :email,
            :event_question_id,
            :nickname,
            :image_profile,
            :answer,
            :gender,
            :profile,
            :prefecture_id,
            :living_prefecture_id,
            :living_city,
            :living_address,
            :age,
            event_ids: []
        )
    end


end
