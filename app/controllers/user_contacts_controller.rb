class UserContactsController < ApplicationController
  include Circlebook

  before_action :authenticate_admin_user!, only: [:contact_list, :update_contact]
  before_action :set_users, {except: [:contact_block, :contact_list, :check_thanks]}

  def new
    @user_contact = @user.user_contacts.build
    @admin_users = AdminUser.where(check: nil)
    @admin_ids = @admin_users.select(:id)
    @users = User.ng_account.prefecture(@user.prefecture_id).event(@user.event_id).where(switch: "募集中", admin_user_id: @admin_ids).where.not(id: @user.id).order(:last_post => :desc)

    # 荒らし対応
    @account_block = UserContact.where(ip_address: request.remote_ip, account_block: "block")
    if @account_block.present?
      @db_validation_error = DbValidationError.new
      @db_validation_error.name = "UserContact_block"
      @db_validation_error.content_01 = request.remote_ip
      @db_validation_error.save

      flash[:notice] = "アカウントをロックしました"
      redirect_to contact_block_path
    end

    case params[:entry]
    when "1"
      @user_contact.entry = "見学"
      @user.template = "性別： 例）男\r\n年代： 例）30代\r\n経歴： 例）初心者\r\n\r\n▼メッセージ\r\n例）初心者ですがよろしくお願いします！\r\n" if @user.template.blank?
      @place_holder = @user.template
    when "2"
      @user_contact.entry = "練習試合"
      @user.template = "種　目：例）バスケ\r\nエリア：例）東京都\r\n年齢層：例）30代中心\r\n構　成：例）10名程度\r\nレベル：例）初心者多め\r\n"
      @place_holder = @user.template
    when "3"
      @user_contact.entry = "質問"
      @user.template = ""
      @place_holder = "例）次の活動日はいつですか？"
    else
      @user_contact.entry = "参加"
      @user.template = "性別： 例）男\r\n年代： 例）30代\r\n経歴： 例）初心者\r\n\r\n▼メッセージ\r\n例）初心者ですがよろしくお願いします！\r\n" if @user.template.blank?
      @place_holder = @user.template
    end

    @user_contact.message = @user.template

  end

  def edit
  end

  def index
    redirect_to new_user_user_contact_path(@user)
  end


	def create
		@user.user_contacts.create(user_contact_params)
		@user_contact = @user.user_contacts.last
    @user_contact.random_id = SecureRandom.alphanumeric(16)
    @user_contact.ip_address = request.remote_ip

    # 荒らし対応
    @same_contacts = UserContact.where(ip_address: @user_contact.ip_address, message: @user_contact.message)
    if @same_contacts.count >= 6 # 7回目からブロック
      @user_contact.account_block = "block"
    end

    if @user_contact.save
      ContactMailer.send_contact(@user, @user_contact).deliver
      ContactMailer.send_member(@user, @user_contact).deliver
      if @user.sent_count.present?
        @user.sent_count = @user.sent_count + 1
      else
        @user.sent_count = 1
      end
      @user.save

      flash[:notice] = "お問い合わせありがとうございます！"
      redirect_to "/users/#{@user.id}/thanks/#{@user_contact.random_id}"

    else
      # バリデーションエラー値の保存
      @db_validation_error = DbValidationError.new
      @db_validation_error.name = "UserContact" + "_#{@user_contact.entry}"
      @db_validation_error.content_01 = @user_contact.name
      @db_validation_error.content_02 = @user_contact.mail + "/" + @user_contact.mail_confirmation
      @db_validation_error.content_03 = @user_contact.message
      @db_validation_error.save
      render "/user_contacts/edit"
    end


	end

	def thanks
    @user_contact = UserContact.find_by(random_id: params[:random_id])
    @users = User.ng_account.prefecture(@user.prefecture_id).event(@user.event_id).where(switch: "募集中").where.not(id: @user.id).order(:last_post => :desc)
	end

	def check_thanks
	end

  def respond_check
    if UserContact.find_by(random_id: params[:random_id])
      @user = User.find_by(id: params[:user_id])
      @user_contact = UserContact.find_by(random_id: params[:random_id])

      if @user.id != @user_contact.user_id
        flash[:notice] = "URLが間違っています"
        redirect_to circle_path(@user.id)
      end

    else
      flash[:notice] = "URLが間違っています"
			redirect_to circle_path(@user.id)
    end
  end

  def check_reaction
    if UserContact.find_by(random_id: params[:random_id])
      @user = User.find_by(id: params[:user_id])
      @user_contact = UserContact.find_by(random_id: params[:random_id])

      if @user.id != @user_contact.user_id
        flash[:notice] = "URLが間違っています"
        redirect_to circle_path(@user.id)
      end

    else
      flash[:notice] = "URLが間違っています"
			redirect_to circle_path(@user.id)
    end
  end


  def check_violation
    if UserContact.find_by(random_id: params[:random_id])
      @user = User.find_by(id: params[:user_id])
      @user_contact = UserContact.find_by(random_id: params[:random_id])

      if @user.id != @user_contact.user_id
        flash[:notice] = "URLが間違っています"
        redirect_to circle_path(@user.id)
      end

    else
      flash[:notice] = "URLが間違っています"
			redirect_to circle_path(@user.id)
    end
  end


  def update
    @user_contact = UserContact.find(params[:id])
    if @user_contact.violation.present?
      # 違反報告
      if @user_contact.update(user_contact_params)
        OpinionMailer.send_violation(@user, @user_contact).deliver
        flash[:notice] = 'ご報告ありがとうございます！'
        redirect_to "/check/thanks"
      else
        flash[:notice] = 'エラーです'
        redirect_to circles_path
      end
    else
      # 返信なしの報告
      if @user_contact.update(user_contact_params)
        flash[:notice] = 'ご報告ありがとうございます！'
        redirect_to "/check/thanks"
      else
        flash[:notice] = 'エラーです'
        redirect_to circles_path
      end
    end

  end



  def contact_block
  end

  def contact_list
		if admin_user_signed_in?
			@user = User.find(params[:id])
      @respond_check_count = UserContact.where(user_id: @user.id, respond_check: "NG").count
      @admin_user = current_admin_user
      @user_contacts = UserContact.where(user_id: @user.id, contact_del: nil).order(updated_at: :desc).page(params[:page]).per(10)

			if current_admin_user.id == @user.admin_user_id
				# OK
			elsif current_admin_user.id == 1
				#OK
			else
        flash[:notice] = "権限がありません"
        redirect_to circles_path
			end
		end

		# パンくず
		@b1_name = @user.name
		@b1_url = "/users/#{@user.id}"
		@b2_name = "マイページ"
		@b2_url = "/users/#{@user.id}/mypage"
		@b3_name = "お問い合わせ管理"
		@b3_url = ""
  end

  def update_contact
    @user = User.find(params[:user_id])
    @user_contact = UserContact.find(params[:id])

    case params[:submit]
      when "update"
        if @user_contact.update(user_contact_params)
          flash[:notice] = "更新完了しました！"
          redirect_to "/users/#{@user.id}/contact_list"
        else
          flash[:notice] = "エラーが発生しました"
          redirect_to "/users/#{@user.id}/contact_list"
        end

      when "delete"
        @user_contact.contact_del = "非表示"
        @user_contact.respond_check = nil
        if @user_contact.update(user_contact_params)
          cb_point(@user)
          @user.save
          flash[:notice] = "削除しました"
          redirect_to "/users/#{@user.id}/contact_list"
        else
          flash[:notice] = "エラーが発生しました"
          redirect_to "/users/#{@user.id}/contact_list"
        end

      when "report"

        # 荒らし対応
        @yellow_card = UserContact.where(ip_address: @user_contact.ip_address, account_block: "yellow_card")
        if @yellow_card.count >= 1 # 2回目からブロック
          @user_contact.account_block = "block"
        else
          @user_contact.account_block = "yellow_card"
        end

        if @user_contact.update(user_contact_params)
          flash[:notice] = "違反通報を受け付けました"
          redirect_to "/users/#{@user.id}/contact_list"
        else
          flash[:notice] = "エラーが発生しました"
          redirect_to "/users/#{@user.id}/contact_list"
        end

      when "respond"
        @user_contact.respond_check = nil
        if @user_contact.update(user_contact_params)
          cb_point(@user)
          @user.save
          flash[:notice] = "更新しました"
          redirect_to "/users/#{@user.id}/contact_list"
        else
          flash[:notice] = "エラーが発生しました"
          redirect_to "/users/#{@user.id}/contact_list"
        end

    end

  end






private
	def user_contact_params
		params.require(:user_contact).permit(:mail, :mail_confirmation, :name, :message, :entry, :respond_check, :random_id, :ip_address, :account_block, :contact_del, :comment, :violation)
	end

	def set_users
    @user = User.find_by(id: params[:user_id])
    @respond_check_count = UserContact.where(user_id: @user.id, respond_check: "NG").count
    if InvalidEmail.find_by(email: @user.admin_user.email)
      @invalid = "無効"
    else
      @invalid = "有効"
    end

  end


end
