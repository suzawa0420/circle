class ReviewsController < ApplicationController

  include Circlebook

  before_action :set_member, except: [:all_reviews]
  before_action :ensure_correct_member, only: [:edit, :update, :destroy]
  before_action :protect_submission, only: :create

	def index
		@review = @user.reviews.build
		@reviews = Review.where(user_id: @user.id).order(created_at: :DESC)
    @ip = Review.where(user_id: @user.id, ip: request.remote_ip)
		@b4_name = "口コミ・評価"
		@b4_url = ""
	end

	def new
	end

  def create
    @review = @user.reviews.build(review_params)
    @review.ip = request.remote_ip
    @review.member_id = current_member.id if member_signed_in?
    saved = false
    @user.with_lock do
      duplicate = @user.reviews.exists?(ip: request.remote_ip)
      duplicate ||= member_signed_in? && @user.reviews.exists?(member_id: current_member.id)
      if duplicate
        render plain: 'このサークルにはすでに投稿済みです。', status: :conflict
        return
      end
      if @review.save
        refresh_review_score
        saved = true
      end
    end

    if saved
      invalid_email = InvalidEmail.exists?(email: @user.admin_user.email)
      if @review.review == 1 && @user.switch == '募集中' && !invalid_email
        @user.update!(last_post: Time.zone.now)
        ReviewMailer.send_review(@user).deliver
      elsif @review.review == 0
        ReviewMailer.bad_review(@user).deliver
      end
      flash[:notice] = '投稿が完了しました！'
    else
      flash[:notice] = 'コメントは6〜2000文字で入力してください。URLやNGワードは投稿できません。'
    end
    redirect_to user_reviews_path(@user)
  end

  def update
    saved = false
    @user.with_lock do
      if @review.update(review_params)
        refresh_review_score
        saved = true
      end
    end
    if saved
      redirect_to user_reviews_path(@user), notice: '編集が完了しました！'
    else
      render 'edit', status: :unprocessable_entity
    end
  end

  def edit; end

  def destroy
    @user.with_lock do
      @review.destroy!
      refresh_review_score
    end
    redirect_to user_reviews_path(@user), notice: '削除しました'
  end

  def all_reviews
    @reviews = Review.all.order(updated_at: "ASC")

    @b1_name = "サークルブック内の口コミ・評価"
    @b1_url = ""
  end


  private
	def set_member
    @user = User.find(params[:user_id])
    @prefectures = Prefecture.all

		if member_signed_in?
			@member = current_member
			@member_reviews = Review.where(user_id: @user.id, member_id: @member.id)
		end

    if @user.present?
      if @user.switch.present?
      @b1_name = @user.event.name
      @b1_url = "/#{@user.event.ruby}"
      @b2_name = @user.prefecture.name
      @b2_url = "/#{@user.event.ruby}/#{@user.prefecture.kana}"
      @b3_name = @user.name
      @b3_url = "/users/#{@user.id}"
      end
		end
  end


  def review_params
    params.require(:review).permit(:review, :comment, :age, :gender, :nickname)
  end

  def ensure_correct_member
    @review = @user.reviews.find(params[:id])
    owner = member_signed_in? && @review.member_id == current_member.id
    master = admin_user_signed_in? && current_admin_user.master_account?
    render plain: '権限がありません。', status: :forbidden unless owner || master
  end

  def protect_submission
    return unless verify_spam_form!("review:#{@user.id}")
    if @user.review_permit == false || AccountBlock.exists?(ip_address: request.remote_ip)
      render plain: '現在、口コミを投稿できません。', status: :forbidden
    end
  end

  def refresh_review_score
    @user.review_score = @user.reviews.average(:review).to_f * 5
    cb_point(@user)
    @user.save!
  end
end
