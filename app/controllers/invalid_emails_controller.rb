class InvalidEmailsController < ApplicationController

  before_action :webmaster

  def index
    @invalid_email = InvalidEmail.new
    @invalid_emails = InvalidEmail.all
  end

  def create
    @invalid_email = InvalidEmail.new(invalid_email_params)
    if @invalid_email.update(invalid_email_params)
			flash[:notice] = "追加しました"
			redirect_to invalid_emails_path
    else
			flash[:notice] = "エラー"
			redirect_to invalid_emails_path
    end
  end

  def destroy
		@invalid_email = InvalidEmail.find(params[:id])
		@invalid_email.destroy

		flash[:notice] = "削除しました"
		redirect_to invalid_emails_path
  end



  private
	def invalid_email_params
		params.require(:invalid_email).permit(:email)
	end

  def webmaster
    require_webmaster!
  end

end
