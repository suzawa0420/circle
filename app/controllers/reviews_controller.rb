class ReviewsController < ApplicationController
  include Circlebook
  before_action :set_circle, except: :all_reviews

  def index
    @reviews = @user.reviews.includes(:member, :conversation_review).order(created_at: :desc)
    @conversation = member_signed_in? ? Conversation.find_by(user: @user, member: current_member) : nil
  end

  def new
    redirect_to user_reviews_path(@user)
  end

  def create
    render plain: '口コミは、主催者から返信を受けたチャット画面で投稿してください。', status: :forbidden
  end

  def edit
    render plain: '公開済みの口コミは編集できません。', status: :forbidden
  end
  alias_method :update, :edit

  def destroy
    review = @user.reviews.find(params[:id])
    owner = member_signed_in? && review.member_id == current_member.id
    return head :forbidden unless owner || webmaster?

    if review.conversation_review
      review.conversation_review.conversation.delete_review!('member')
    elsif review.member.present?
      # Preserve the one-review entitlement even after deleting a legacy review.
      conversation = Conversation.create_or_find_by!(user: @user, member: review.member) { |record| record.legacy_member_review = true }
      conversation.with_lock do
        conversation.update!(legacy_member_review: true)
        review.destroy!
        conversation.refresh_circle_score!
      end
    else
      @user.with_lock do
        review.destroy!
        @user.review_score = @user.reviews.average(:review).to_f * 5
        CircleScoreUpdater.new.refresh(@user)
        @user.save!
      end
    end
    redirect_to user_reviews_path(@user), notice: '口コミを削除しました。このサークルへの再投稿はできません。'
  end

  def all_reviews
    @reviews = Review.includes(:user, :member).order(updated_at: :desc).page(params[:page]).per(30)
    @b1_name = 'サークルブック内の口コミ・評価'
    @b1_url = ''
  end

  private

  def set_circle
    @user = User.find(params[:user_id])
    @prefectures = Prefecture.all
    if @user.switch.present?
      @b1_name, @b1_url = @user.event.name, "/#{@user.event.ruby}"
      @b2_name, @b2_url = @user.prefecture.name, "/#{@user.event.ruby}/#{@user.prefecture.kana}"
      @b3_name, @b3_url = @user.name, circle_path(@user)
    end
    @b4_name, @b4_url = '口コミ・評価', ''
  end
end
