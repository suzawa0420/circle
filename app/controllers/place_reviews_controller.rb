class PlaceReviewsController < ApplicationController
  before_action :set_place
  before_action :protect_submission, only: :create
  before_action :require_master_account, only: :destroy

  def index; end
  def new; end
  def update; end
  def edit; end
  def destroy
    @place.with_lock do
      @place.place_reviews.find(params[:id]).destroy!
      refresh_place_scores
    end
    redirect_back(fallback_location: root_path, notice: '口コミを削除しました。')
  end

  def create
    @place_review = @place.place_reviews.build(place_review_params)
    @place_review.ip_address = request.remote_ip
    saved = false

    # Serialize duplicate checks and aggregate updates for this facility.
    @place.with_lock do
      if @place.place_reviews.exists?(ip_address: request.remote_ip)
        render plain: 'この施設にはすでに投稿済みです。', status: :conflict
        return
      end
      if @place_review.valid?
        @place_review.average_score = %i[facility reservation price access].sum { |key| @place_review.public_send(key) } / 4.0
        @place_review.save!
        refresh_place_scores
        saved = true
      end
    end

    flash[:notice] = saved ? '投稿ありがとうございます！' : '評価は0〜5、コメントは6〜2000文字で入力してください。URLは投稿できません。'
    redirect_back(fallback_location: root_path)
  end

  private

  def require_master_account
    unless admin_user_signed_in? && current_admin_user.master_account?
      render plain: '権限がありません。', status: :forbidden
    end
  end

  def refresh_place_scores
    averages = %i[facility reservation price access].to_h do |key|
      ["average_#{key}", @place.place_reviews.average(key)&.to_f]
    end
    score = averages.values.all? ? averages.values.sum / 4.0 : nil
    @place.update_columns(averages.merge('average_score' => score))
  end

  def protect_submission
    return unless verify_spam_form!("place_review:#{@place.id}")
    if AccountBlock.exists?(ip_address: request.remote_ip)
      render plain: '現在、この接続元からは投稿できません。', status: :forbidden
    end
  end

  def place_review_params
    params.require(:place_review).permit(:facility, :reservation, :price, :access, :event_id, :comment)
  end

  def set_place
    @place = Place.find(params[:place_id])
  end
end
