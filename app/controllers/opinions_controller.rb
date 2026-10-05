class OpinionsController < ApplicationController
  before_action :authenticate_owner_or_webmaster!

  def new
    redirect_to new_support_request_path(kind: 'suggestion', category: 'other')
  end
  alias_method :index, :new

  def create
    user = User.find(params[:user_id])
    return head :forbidden unless can_manage_circle?(user)
    opinion = user.opinions.build(params.require(:opinion).permit(:opinion))
    if opinion.opinion.to_s.length <= 4000 && opinion.save
      redirect_to support_thanks_path, notice: 'ご意見を受け付けました。個別の返信は原則行いません。'
    else
      redirect_to new_support_request_path(kind: 'suggestion', category: 'other'), alert: 'ご意見の入力内容を確認してください。'
    end
  end
end
