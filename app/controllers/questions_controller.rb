class QuestionsController < ApplicationController

  include Circlebook
	before_action :set_user
	before_action :authenticate_owner_or_webmaster!, only: [:update, :destroy]
	before_action :authorize_question_owner, only: [:update, :destroy]


	def index
		@question = @user.questions.build
    @questions = Question.where(user_id: @user.id).order(id: "DESC").page(params[:page])
	end

	def question
		@question = @user.questions.build
		@questions = Question.where(user_id: @user.id).order(id: "DESC").page(params[:page])

		if params[:sample] == "first"
			@question_sample = @question_first

		elsif params[:sample] == "second"
			@question_sample = @question_second

		elsif params[:sample] == "third"
			@question_sample = @question_third

		else

		end

		if @user.switch.present?
		@b5_name = @question_sample
		@b5_url = ""
		end

	end


	def new

	end

	def edit
    @questions = Question.where(user_id: params[:user_id]).order(id: "DESC")
	end

	def create
    @questions = Question.where(user_id: params[:user_id]).order(id: "DESC")
    if InvalidEmail.find_by(email: @user.admin_user.email)
      @invalid = "無効"
    else
      @invalid = "有効"
    end

		@question = @user.questions.build(question_params)
		if @question.valid?
			@question.content = @question.content.gsub(/[^!！？、。ー〜0-9０-９A-Za-zＡ-Ｚａ-ｚ-ぁ-んァ-ン一-龥]/, '')
      @question.ip_address = request.remote_ip

			if @question.save

				if admin_user_signed_in?
					if current_admin_user.id == @user.admin_user_id
            record_circle_activity(@user, @question) if @question.answer.present?
            cb_point(@user)
            @user.save
					end

				elsif @user.switch == "募集中" && @invalid == "有効"
					UserMailer.send_when_create(@user, @question).deliver
        else
				end

				flash[:notice] = '送信しました！'
				redirect_to user_questions_path(@user)

			else
        # バリデーションエラー値の保存
        @db_validation_error = DbValidationError.new
        @db_validation_error.name = "Question"
        @db_validation_error.content_01 = @question.content
        @db_validation_error.save

				render "/questions/edit"
			end

		else

			flash[:notice] = '質問が空欄です'
			render user_questions_path(@user)
		end



	end

	def update
		@question = @user.questions.find(params[:id])

		if @question.update(question_params)

      record_circle_activity(@user, @question) if @question.saved_change_to_answer? && @question.answer.present?
      cb_point(@user)
			@user.save

			flash[:notice] = '更新しました！'
			redirect_to user_question_path
		end

	end

	def show
		@question = @user.questions.find(params[:id])
		@questions = Question.where(user_id: @user.id).order(id: "DESC").page(params[:page])

		if @user.switch.present?
		@b5_name = @question.content
		@b5_url = ""
		end

	end



	def destroy
		@question = @user.questions.find(params[:id])
		@question.destroy

    cb_point(@user)
    @user.save

		flash[:notice] = "削除しました"
		redirect_to user_questions_path
	end





  private
	def authorize_question_owner
		unless can_manage_circle?(@user)
			render plain: '権限がありません。', status: :forbidden
		end
	end

	def set_user
    @user = User.find(params[:user_id])

    @question_first = "活動頻度を教えてください！"
    @question_second = "１人でも参加しやすいですか？"
    @question_third = "参加者の年齢層はどれくらいですか？"

    if @user.present?
			if @user.switch.present?
			@b1_name = @user.event.name
			@b1_url = "/#{@user.event.ruby}"
			@b2_name = @user.prefecture.name
			@b2_url = "/#{@user.event.ruby}/#{@user.prefecture.kana}"	
			@b3_name = @user.name
			@b3_url = "/users/#{@user.id}"
			@b4_name = "質問コーナー"
			@b4_url = "/users/#{@user.id}/questions"
			end
		end


    end

    def question_params
      params.require(:question).permit(:content, :answer)
    end



end
