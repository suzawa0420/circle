class OrganizerProfilesController < ApplicationController
  before_action :authenticate_admin_user!
  before_action :set_organizer

  def edit
  end

  def update
    if @admin_user.update(profile_params)
      redirect_to edit_organizer_profile_path, notice: '主催者プロフィールを更新しました。'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_organizer
    @admin_user = current_admin_user
  end

  def profile_params
    permitted = params.require(:admin_user).permit(:nickname, :image_profile, :profile, :prefecture_id, :age, :open)
    permitted.merge!(params.require(:admin_user).permit(:gender)) if @admin_user.gender.blank?
    permitted
  end
end
