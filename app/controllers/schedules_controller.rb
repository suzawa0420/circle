class SchedulesController < ApplicationController

include Circlebook

before_action :ensure_correct_user, {only: [:edit, :update, :new]}
before_action :set_schedules, {except: [:secret, :attendance, :attendance_create, :attendance_update, :attendance_delete, :dates, :day, :year, :month]}
before_action :set_dates, {only: [:dates, :day]}


	def index
		@schedule = @user.schedules.build

		@b1_name = @user.name
		@b1_url = "/users/#{@user.id}"
		@b2_name = "活動スケジュール"
		@b2_url = ""
	end

  def new
		@schedule = @user.schedules.build
    @btn_name = "新規作成"

    @copy_schedules = Schedule.where(user_id: @user.id).order(:day => :asc, :time_s => :asc).last(10)

    if params[:copy]
      @copy_schedule = Schedule.find(params[:copy])
      if @user.id != @copy_schedule.user.id
        flash[:notice] = "URLに誤りがあります"
        redirect_to new_user_schedule_path
      end
    end

		@b1_name = @user.name
		@b1_url = "/users/#{@user.id}"
		@b2_name = "スケジュールの新規追加"
		@b2_url = ""
  end

	def create
    if params[:copy]
      @copy_schedule = Schedule.find(params[:copy])
      if @user.id != @copy_schedule.user.id
        flash[:notice] = "URLに誤りがあります"
        redirect_to new_user_schedule_path
      end
    end

    @schedule = @user.schedules.new(schedule_params)
    @btn_name = "更新する"

		if @schedule.save

      @schedule = Schedule.where(user_id: @user.id).last
      @schedule.date = Time.parse(@schedule.day).strftime("%Y年%-m月%-d日(#{%w(日曜日 月曜日 火曜日 水曜日 木曜日 金曜日 土曜日)[Time.parse(@schedule.day).wday]})")
      if params[:copy]
        if @schedule.top_image.blank?
          @schedule.top_image = @copy_schedule.top_image.file
        end
        if @schedule.recruitment_numbers.blank?
          @schedule.recruitment_numbers = @copy_schedule.recruitment_numbers
        end
      end
      @schedule.save

      last_post(@user)
      cb_point(@user)
      @user.save

      flash[:notice] = "追加しました！"
      redirect_to user_schedules_path
    else
      render "new"
    end

  end

	def update
		@schedule = Schedule.find(params[:id])

    if @schedule.name_schedules.where(answer: 1).size > schedule_params[:recruitment_numbers].to_i && schedule_params[:recruitment_numbers].to_i != 0
      flash[:notice] = "募集人数がオーバーしています"
      render "edit"

    else
      if @schedule.update(schedule_params)

        @user.user_time = Time.now
        @user.save

        flash[:notice] = '更新完了！'
        redirect_to user_schedules_path
      else
        render "edit"
      end
    end





  end


	def show
		@schedule = Schedule.find(params[:id])

		if @schedule.title.present?
			@schedule_title = @schedule.title.gsub(/[^！？!?ー〜0-9A-Za-z-ぁ-んァ-ン一-龥]/, '')
		else
			@schedule_title = @user.event.name
		end

		if @user.id.to_i != @schedule.user_id.to_i
			flash[:notice] = "存在しないURLです"
			redirect_to "/users"
		end

    # meta_tag
    @meta_title = "#{Time.parse(@schedule.day).strftime("%-m月%-d日(#{@wdays[Time.parse(@schedule.day).wday]})")}の活動内容｜#{@schedule.title}｜#{@user.name}"
    @meta_description = "#{Time.parse(@schedule.day).strftime("%-m月%-d日(#{@wdays[Time.parse(@schedule.day).wday]})")}#{ @schedule.time_s.strftime('%H:%M') if @schedule.time_s.present? }#{"〜" if @schedule.time_s.present? }#{ @schedule.time_e.strftime('%H:%M') if @schedule.time_e.present? }@#{ @schedule.venue }の活動内容｜#{@schedule.title}｜#{@user.name}"

		@b1_name = @user.name
		@b1_url = "/users/#{@user.id}"
		@b2_name = "活動スケジュール"
		@b2_url = "/users/#{@user.id}/schedules"
		@b3_name = Time.parse(@schedule.day).strftime("%Y/%-m/%-d(#{%w(日 月 火 水 木 金 土)[Time.parse(@schedule.day).wday]})")
		@b3_url = ""
	end

	def secret
    @schedule = Schedule.find(params[:id])
    @user = User.find_by(unique_id: params[:unique_id])
    @schedules = Schedule.where(user_id: @user.id).where("day > ?", DateTime.yesterday).order(:day => :asc, :time_s => :asc)
    @past_schedules = Schedule.where(user_id: @user.id).where("day < ?", DateTime.yesterday).order(:day => :desc, :time_s => :asc)
    @data = AdminUser.find_by(id: params[:user_id])
    @prefectures = Prefecture.all
    @schedule_month = 0
    @schedule_m_c = 0
    @contact_judge = "_s"

		if @schedule.title.present?
			@schedule_title = @schedule.title.gsub(/[^！？!?ー〜0-9A-Za-z-ぁ-んァ-ン一-龥]/, '')
		else
			@schedule_title = @user.event.name
		end

		if @user.id.to_i != @schedule.user_id.to_i
			flash[:notice] = "存在しないURLです"
			redirect_to "/users"
		end


		@b1_name = @user.name
		@b1_url = "/users/#{@user.id}"
		@b2_name = "活動スケジュール"
		@b2_url = "/users/#{@user.id}/schedules"
		@b3_name = Time.parse(@schedule.day).strftime("%Y/%-m/%-d(#{%w(日 月 火 水 木 金 土)[Time.parse(@schedule.day).wday]})")
		@b3_url = ""
	end

	def edit
		@schedule = Schedule.find(params[:id])
    @btn_name = "更新する"

		@b1_name = @user.name
		@b1_url = "/users/#{@user.id}"
		@b2_name = "スケジュールの編集"
		@b2_url = ""
	end

	def destroy
		@schedule = @user.schedules.find(params[:id])
		@schedule.destroy

    cb_point(@user)
    ≈.save

    flash[:notice] = "削除しました"
		redirect_to user_schedules_path
	end



# スケジュール
def dates
  @schedules = Schedule.where("day > ?", DateTime.yesterday).order(:day => :asc, :time_s => :asc).page(params[:page]).per(20)

  @b1_name = "イベント一覧"
  @b1_url = ""
end

def year
  redirect_to :action => 'dates', :status => 301
end

def month
  redirect_to :action => 'dates', :status => 301
end

def day
  @date = "#{params[:year]}-#{params[:month]}-#{params[:day]}"
  @day = Time.parse(@date).strftime("%Y年%-m月%-d日(#{@wdays[Time.parse(@date).wday]})")
  @categories = Category.all.order(:id => :asc)
  @events = Event.all.order(:order => :asc)
  @prefectures = Prefecture.all.order(:order => :asc)
  @event = Event.find_by(ruby: params[:event])
  @prefecture = Prefecture.find_by(kana: params[:pref])

  if params[:event].present? && params[:pref].present?
    @users = User.event(@event.id).prefecture(@prefecture.id)
    @user_ids = @users.select(:id)
    @schedules = Schedule.joins(:user).includes(:user).where(day: @date, user_id: @user_ids).order(:day => :asc).order("users.last_post desc").page(params[:page]).per(20)

  elsif params[:event].present?
    @users = User.event(@event.id)
    @user_ids = @users.select(:id)
    @schedules = Schedule.joins(:user).includes(:user).where(day: @date, user_id: @user_ids).order(:day => :asc).order("users.last_post desc").page(params[:page]).per(20)

  elsif params[:pref].present?
    @users = User.prefecture(@prefecture.id)
    @user_ids = @users.select(:id)
    @schedules = Schedule.joins(:user).includes(:user).where(day: @date, user_id: @user_ids).order(:day => :asc).order("users.last_post desc").page(params[:page]).per(20)

  else
    @schedules = Schedule.joins(:user).includes(:user).where(day: @date).order(:day => :asc).order("users.last_post desc").page(params[:page]).per(20)
  end

  @b1_name = "イベント一覧"
  @b1_url = "/dates"
  @b2_name = "#{Time.parse(@date).strftime("%Y年")}"
  @b2_url = "/dates/#{params[:year]}"
  @b3_name = "#{Time.parse(@date).strftime("%-m月")}"
  @b3_url = "/dates/#{params[:year]}/#{params[:month]}"
  @b4_name = "#{@day}に開催予定のイベント一覧"
  @b4_url = ""
end

private
  def set_schedules
    @user = User.find(params[:user_id])
    @schedules = Schedule.where(user_id: @user.id).where("day > ?", DateTime.yesterday).order(:day => :asc, :time_s => :asc)
    @past_schedules = Schedule.where(user_id: @user.id).where("day <= ?", DateTime.yesterday).order(:day => :desc, :time_s => :asc).page(params[:page])
    @data = AdminUser.find_by(id: params[:user_id])
    @prefectures = Prefecture.all
    @schedule_month = 0
    @schedule_m_01 = 0
    @schedule_m_02 = 0
    @wdays =  ["日", "月", "火", "水", "木", "金", "土" ]

    @mail_title = "【#{@user.name}】お問い合わせ"
    @mail_message = "こちらに相談内容をご記入ください！"
  end

  def set_attendances
    @user = User.find_by(unique_id: params[:unique_id])
    @schedules = Schedule.where(user_id: @user.id).where("day > ?", DateTime.yesterday).order(:day => :asc, :time_s => :asc)
    @past_schedules = Schedule.where(user_id: @user.id).where("day <= ?", DateTime.yesterday).order(:day => :desc, :time_s => :asc)
  end

  def set_dates
    @wdays =  ["日", "月", "火", "水", "木", "金", "土" ]
    if admin_user_signed_in?
      @user = current_admin_user.users.last
    end
  end


  def ensure_correct_user
    @user = User.find(params[:user_id])

    if current_admin_user.id.to_i == @user.admin_user_id.to_i

    elsif current_admin_user.id == 1

    else
      flash[:notice] = "権限がありません"
      redirect_to circles_path

    end
  end

  def schedule_params
    params.require(:schedule).permit(:day, :venue, :date, :time_s, :time_e, :venue_address, :note, :title, :google_map, :recruitment, :member_venue, :recruitment_numbers, :cost, :top_image)
  end

  def name_params
    params.require(:name).permit(:name, :gender, schedule_ids:[], name_schedules_attributes: [:answer, :comment, :schedule_id, :name_id, :_destroy, :id])
  end


end
