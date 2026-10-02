class AccountBlocksController < ApplicationController

  before_action :webmaster, {only: [:index, :destroy]}

  def index
    @account_blocks = AccountBlock.all.order(created_at: "DESC")
  end

  def destroy
		@account_block = AccountBlock.find(params[:id])
		@account_block.destroy

		flash[:notice] = "削除しました"
		redirect_to account_blocks_path
  end

  def question_block
    @user = User.find_by(id: params[:user_id])
    @question = Question.find(params[:id])

    if can_manage_circle?(@user)
      @account_block = AccountBlock.new
      @account_block.block = 1
      @account_block.ip_address = @question.ip_address
      @account_block.model = "Question"
      @account_block.url = request.url
      @account_block.save

      flash[:notice] = "通報しました"
      redirect_to user_questions_path

    else
      flash[:notice] = "権限がありません"
      redirect_to circles_path
    end

  end


  def review_block
    @user = User.find_by(id: params[:user_id])
    @review = Review.find(params[:id])

    if can_manage_circle?(@user)
      @account_block = AccountBlock.new
      @account_block.block = 1
      @account_block.ip_address = @review.ip
      @account_block.model = "Review"
      @account_block.url = request.url
      @account_block.save

      flash[:notice] = "通報しました"
      redirect_to user_reviews_path

    else
      flash[:notice] = "権限がありません"
      redirect_to circles_path
    end

  end


  private
  def webmaster
    require_webmaster!
  end


end
