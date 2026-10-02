class Webmasters::SessionsController < Devise::SessionsController
  skip_before_action :set_imperfect_current_user
  layout 'webmaster'

  private

  def after_sign_in_path_for(resource)
    webmaster_path
  end

  def after_sign_out_path_for(resource_or_scope)
    new_webmaster_session_path
  end
end
