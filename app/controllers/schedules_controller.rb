class SchedulesController < ApplicationController

include Circlebook

before_action :authenticate_owner_or_webmaster!, only: [:new, :create, :edit, :update, :destroy]
before_action :ensure_correct_user, only: [:new, :create, :edit, :update, :destroy]
before_action :set_schedules, {except: [:secret, :attendance, :attendance_create, :attendance_update, :attendance_delete, :dates, :day, :today, :tomorrow, :year, :month]}
before_action :set_dates, {only: [:dates, :day, :today, :tomorrow]}


	def index
		@schedule = @user.schedules.build
    @calendar = ScheduleCalendarData.new(user: @user, month: params[:month], date: params[:date],
      past: params[:past] == '1' || params[:page].present?, page: params[:page])

		@b1_name = @user.name
		@b1_url = "/users/#{@user.id}"
		@b2_name = "活動スケジュール"
		@b2_url = ""
	end

  def new
		@schedule = @user.schedules.build
    @btn_name = "新規作成"

    set_copy_schedules
    set_copy_schedule
    if @copy_schedule
      @schedule.assign_attributes(@copy_schedule.attributes.slice(
        'time_s', 'time_e', 'venue', 'cost', 'member_venue', 'venue_address',
        'title', 'note', 'recruitment_numbers', 'google_map'
      ))
      @schedule.day = (Date.parse(@copy_schedule.day) + 7).iso8601 if params[:copy_mode] == 'next_week'
    end

		@b1_name = @user.name
		@b1_url = "/users/#{@user.id}"
		@b2_name = "スケジュールの新規追加"
		@b2_url = ""
  end

	def create
    set_copy_schedule

    @schedule = @user.schedules.new(schedule_params)
    @btn_name = "更新する"

		if @schedule.save

      record_circle_activity(@user, @schedule)

      @schedule = Schedule.where(user_id: @user.id).last
      @schedule.date = Time.parse(@schedule.day).strftime("%Y年%-m月%-d日(#{%w(日曜日 月曜日 火曜日 水曜日 木曜日 金曜日 土曜日)[Time.parse(@schedule.day).wday]})")
      if @copy_schedule
        if @schedule.top_image.blank?
          @schedule.top_image = @copy_schedule.top_image.file
        end
        if @schedule.recruitment_numbers.blank?
          @schedule.recruitment_numbers = @copy_schedule.recruitment_numbers
        end
      end
      @schedule.save

      cb_point(@user)
      @user.save

      flash[:notice] = "追加しました！"
      redirect_to user_schedules_path
    else
      set_copy_schedules
      @btn_name = "新規作成"
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
    @user.save

    flash[:notice] = "削除しました"
		redirect_to user_schedules_path
	end



# スケジュール
def dates
  @event_date = Time.current.in_time_zone('Tokyo').to_date
  @events = Event.order(:order)
  @prefectures = Prefecture.order(:order)
  @event = Event.find_by!(ruby: params[:event]) if params[:event].present?
  @prefecture = Prefecture.find_by!(kana: params[:pref]) if params[:pref].present?
  @filter_query = { event: @event&.ruby, pref: @prefecture&.kana }.compact
  if params[:date].present?
    raise ActiveRecord::RecordNotFound unless params[:date].is_a?(String) && params[:date].match?(/\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/)
    begin
      date = Date.iso8601(params[:date])
    rescue Date::Error
      raise ActiveRecord::RecordNotFound
    end
    raise ActiveRecord::RecordNotFound unless (1900..2100).cover?(date.year)
    return redirect_to EventDayListing.path(date) + (@filter_query.present? ? '?' + @filter_query.to_query : '')
  end
  @day_listing = EventDayListing.new(date: @event_date, event: @event, prefecture: @prefecture, upcoming: true)
  @schedules = @day_listing.schedules.page(params[:page]).per(20)
  @result_count = @day_listing.total_count
  @event_hub_title = "#{@prefecture&.name || '全国'}の#{@event&.name || 'イベント'}・サークル活動一覧"
  query = @filter_query.dup
  query[:page] = params[:page].to_i if params[:page].to_i > 1
  canonical = 'https://circle-book.com/dates' + (query.present? ? '?' + query.to_query : '')
  set_meta_tags title: @event_hub_title,
    description: "#{@prefecture&.name || '全国'}の#{@event&.name || 'イベント'}の開催予定を一覧で探せます。日付・エリア・ジャンルから絞り込み、時間・場所・募集状況を比較できます。",
    canonical: canonical, noindex: @result_count.zero? || params[:sort].present?,
    og: { image: 'https://circle-book.com/images/dates.jpg' }
  @b1_name = 'イベント一覧'
  @b1_url = ''
end

def year
  redirect_to :action => 'dates', :status => 301
end

def month
  redirect_to :action => 'dates', :status => 301
end

def day
  parts = params.values_at(:year, :month, :day)
  unless parts.all? { |part| part.to_s.match?(/\A[0-9]{1,4}\z/) } &&
         (1900..2100).cover?(parts.first.to_i) && Date.valid_date?(*parts.map(&:to_i))
    raise ActiveRecord::RecordNotFound
  end
  prepare_event_day(Date.new(*parts.map(&:to_i)))
end

def today
  prepare_event_day(Time.current.in_time_zone('Tokyo').to_date, relative: '今日')
  render :day
end

def tomorrow
  prepare_event_day(Time.current.in_time_zone('Tokyo').to_date + 1, relative: '明日')
  render :day
end

private
  def prepare_event_day(date, relative: nil)
    @event_date = date
    @date = date.iso8601
    @day = "#{date.year}年#{date.month}月#{date.day}日（#{@wdays[date.wday]}）"
    @relative_day = relative
    @events = Event.order(:order)
    @prefectures = Prefecture.order(:order)
    @event = Event.find_by!(ruby: params[:event]) if params[:event].present?
    @prefecture = Prefecture.find_by!(kana: params[:pref]) if params[:pref].present?
    @day_listing = EventDayListing.new(date: date, event: @event, prefecture: @prefecture, sort: params[:sort])
    @schedules = @day_listing.schedules.page(params[:page]).per(20)
    @result_count = @day_listing.total_count
    @filter_query = { event: @event&.ruby, pref: @prefecture&.kana }.compact
    @event_day_path = relative ? "/dates/#{action_name}" : EventDayListing.path(date)
    query = @filter_query.dup
    query[:page] = params[:page].to_i if params[:page].to_i > 1
    @event_day_canonical = 'https://circle-book.com' + @event_day_path
    @event_day_canonical += '?' + query.to_query if query.present?
    @event_day_title = "#{relative || @day}#{@prefecture ? '・' + @prefecture.name : ''}の#{@event&.name || 'イベント'}・サークル活動一覧"
    set_meta_tags title: @event_day_title,
      description: "#{relative ? relative + '（' + @day + '）' : @day}に開催予定の#{@prefecture&.name}#{@event&.name || 'イベント'}を探せます。開催時間・場所・募集状況を比較して、気になるサークルの活動詳細を確認できます。",
      canonical: @event_day_canonical,
      noindex: @result_count.zero? || %w[2 3].include?(params[:sort]),
      og: { title: @event_day_title, url: @event_day_canonical }
    raise ActiveRecord::RecordNotFound if params[:page].to_i > 1 && @schedules.empty?
    @b1_name = 'イベント一覧'
    @b1_url = '/dates'
    @b2_name = @event_day_title
    @b2_url = ''
  end

  def set_copy_schedules
    @copy_schedules = @user.schedules.order(:day => :asc, :time_s => :asc).last(10)
  end

  def set_copy_schedule
    @copy_schedule = @user.schedules.find(params[:copy]) if params[:copy].present?
  end

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
    return if webmaster?
    @user = User.find(params[:user_id])

    if current_admin_user.id.to_i == @user.admin_user_id.to_i

    elsif webmaster?

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
