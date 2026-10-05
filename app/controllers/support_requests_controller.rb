class SupportRequestsController < ApplicationController
  include HelpSubmission
  before_action :private_help_page

  def new
    @support_request = SupportRequest.new(kind: SupportRequest::KINDS.key?(params[:kind]) ? params[:kind] : 'inquiry',
      category: HelpCatalog::CATEGORIES.key?(params[:category]) ? params[:category] : 'account',
      audience: admin_user_signed_in? ? 'owner' : (member_signed_in? ? 'member' : 'other'),
      email: current_admin_user&.email || current_member&.email)
    @ready = params[:step] == 'form'
    load_answers
  end

  def create
    return unless verify_spam_form!('support-request')
    @support_request = SupportRequest.new(params.require(:support_request).permit(:kind, :category, :audience, :email, :body))
    @support_request.member = current_member
    @support_request.admin_user = current_admin_user
    @ready = true
    if @support_request.save
      redirect_to support_thanks_path, status: :see_other
    else
      load_answers
      render :new, status: :unprocessable_entity
    end
  end

  def thanks
  end

  private

  def load_answers
    @answers = HelpCatalog.search(category: @support_request.category).first(8)
  end
end
