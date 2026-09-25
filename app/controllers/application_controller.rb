class ApplicationController < ActionController::Base
  include SpamProtection
	before_action :set_current_user
	before_action :set_imperfect_current_user
	before_action :request_path
  before_action :set_data
  before_action :judge_ip
  before_action :set_canonical_url


  private
	def set_current_user
    @current_user = User.find_by(id: session[:user_id]) if session[:user_id]
		if admin_user_signed_in?
			@admin_user = User.find_by(admin_user_id: current_admin_user.id)
		end
  end


  # 登録未完了時のアクション
  def set_imperfect_current_user
    if admin_user_signed_in? #管理人ログイン判定
      if current_admin_user.email == "n.shibazaki@bugs.co.jp" # スーパー管理者は登録不要
        # OK
      elsif current_admin_user.users.any? # 登録1つ以上の判定
        # OK
      elsif controller_path == 'events'
        # OK（Ajax用）
      else
        if  controller_path == 'users' #users コントローラー
          if action_name == 'new' || action_name == 'create' || action_name == 'edit' || action_name == 'update' || action_name == 'edit2' || action_name == 'update2'
            # OK
          else
            flash[:notice] = "登録を完了させてください"
            redirect_to new_user_path
          end
        elsif action_name == 'destroy'

        elsif controller_path == 'pages' || controller_path == 'unsubscribe/admin_users' || controller_path == 'unsubscribe/members'

        else
            flash[:notice] = "登録を完了させてください"
            redirect_to new_user_path
        end
      end

    elsif member_signed_in? #参加者ログイン判定
      if current_member.nickname.present? # 登録1つ以上の判定
        # OK
      else
        if  controller_path == 'members' #members コントローラー
          if action_name == 'new' || action_name == 'create' || action_name == 'edit' || action_name == 'update'
            # OK
          else
            flash[:notice] = "登録を完了させてください"
            redirect_to "/members/#{current_member.id}/edit"
          end
        elsif action_name == 'destroy'

        elsif controller_path == 'pages' || controller_path == 'unsubscribe/admin_users' || controller_path == 'unsubscribe/members'

        else
            flash[:notice] = "登録を完了させてください"
            redirect_to "/members/#{current_member.id}/edit"
        end
      end

    else
      #一般の方
    end
  end



  def authenticate_user
    if @current_user == nil
      flash[:notice] = "ログインが必要です"
      redirect_to login_path
    end
  end

  def forbid_login_user
    if @current_user
      flash[:notice] = "すでにログインしています"
      redirect_to circles_path
    end
  end


	def after_sign_in_path_for(resource)

    if admin_user_signed_in?
        new_user_path

    elsif member_signed_in?
      edit_member_path(current_member)

    elsif exhibition_group_signed_in?
      edit_exhibitor_profile_path

    else

    end

	end


	def request_path
    @path = controller_path + '#' + action_name
    def @path.is(*str)
        str.map{|s| self.include?(s)}.include?(true)
    end
	end

	def set_data
		@time = Time.now
		@url = request.url
  end

  # 荒らし対策
  def judge_ip
    redirect_to root_path if request.remote_ip == "133.106.41.183"
  end

  # ?sort= パラメータをcanonicalから除去してURL重複を防ぐ
  def set_canonical_url
    if params[:sort].present?
      canonical_params = request.query_parameters.except('sort')
      canonical_url = request.base_url + request.path
      canonical_url += "?#{canonical_params.to_query}" if canonical_params.present?
      set_meta_tags canonical: canonical_url
    end
  end


end