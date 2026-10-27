class SchedulesController < ApplicationController

include Circlebook

MANAGEMENT_ACTIONS = %i[new create edit update destroy manage duplicate manage_attendance confirm_delete].freeze
before_action :authenticate_owner_or_webmaster!, only: MANAGEMENT_ACTIONS
before_action :ensure_correct_user, only: MANAGEMENT_ACTIONS
before_action :set_schedules, {except: [:secret, :attendance, :attendance_create, :attendance_update, :attendance_delete, :dates, :day, :today, :tomorrow, :this_week, :next_week, :year, :month]}
before_action :ensure_schedule_visibility, only: %i[index show]
before_action :set_management_schedule, only: %i[manage duplicate manage_attendance confirm_delete]
before_action :private_management_response, only: MANAGEMENT_ACTIONS
before_action :set_dates, {only: [:dates, :day, :today, :tomorrow, :this_week, :next_week]}
before_action :prepare_event_search_filters, only: [:dates, :day, :today, :tomorrow, :this_week, :next_week]


	def index
		@schedule = @user.schedules.build
    @calendar = ScheduleCalendarData.new(user: @user, month: params[:month], date: params[:date],
      past: params[:past] == '1' || params[:page].present?, page: params[:page])
    if can_manage_circle?(@user)
      private_management_response
      @management = ScheduleManagementData.new(user: @user, past: params[:past] == '1', page: params[:page])
    end

		@b1_name = @user.name
		@b1_url = "/users/#{@user.id}"
		@b2_name = "活動スケジュール"
		@b2_url = ""
    if @management
      @b1_name = 'マイページ'
      @b1_url = "/users/#{@user.id}/mypage"
      @b2_name = 'イベント'
    end
	end

  def new
		@schedule = @user.schedules.build
    @schedule_creation_key = SecureRandom.uuid
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

  def manage
    @management = ScheduleManagementData.new(user: @user, schedule: @schedule)
  end

  def duplicate
  end

  def confirm_delete
    @management = ScheduleManagementData.new(user: @user, schedule: @schedule)
  end

  def manage_attendance
    @management = ScheduleManagementData.new(user: @user, schedule: @schedule)
    @attendance_filter = %w[yes no unanswered].include?(params[:answer]) ? params[:answer] : 'all'
    answers = @schedule.name_schedules
    names = Name.joins(:schedules).where(schedules: { user_id: @user.id }).distinct
    names = case @attendance_filter
    when 'yes' then names.where(id: answers.where(answer: 1).select(:name_id))
    when 'no' then names.where(id: answers.where(answer: 0).select(:name_id))
    when 'unanswered' then names.where.not(id: answers.where(answer: [0, 1]).where.not(name_id: nil).select(:name_id))
    else names
    end
    @attendance_names = names.order(updated_at: :desc, id: :desc).page(params[:page]).per(30)
    @attendance_answers = answers.where(name_id: @attendance_names.map(&:id)).order(:id).index_by(&:name_id)
  end

	def create
    set_copy_schedule
    @schedule_creation_key = params[:schedule_creation_key].presence || SecureRandom.uuid
    unless @schedule_creation_key.is_a?(String) && @schedule_creation_key.match?(/\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/)
      raise ActionController::BadRequest
    end

    # Serialize submissions across Puma workers and both production servers.
    @user.with_lock do
      @schedule = @user.schedules.find_by(creation_key: @schedule_creation_key)
      if @schedule
        redirect_to manage_user_schedule_path(@user, @schedule)
      else
        create_schedule
      end
    end
  end

  private def create_schedule
    @schedule = @user.schedules.new(schedule_params)
    @schedule.creation_key = @schedule_creation_key
    @btn_name = "更新する"

    if @schedule.save
      record_circle_activity(@user, @schedule)

      @schedule.date = Time.parse(@schedule.day).strftime("%Y年%-m月%-d日(#{%w(日曜日 月曜日 火曜日 水曜日 木曜日 金曜日 土曜日)[Time.parse(@schedule.day).wday]})")
      if @copy_schedule
        if @schedule.top_image.blank?
          @schedule.top_image = @copy_schedule.top_image.file
        end
        if @schedule.recruitment_numbers.blank?
          @schedule.recruitment_numbers = @copy_schedule.recruitment_numbers
        end
      end
      @schedule.save!

      cb_point(@user)
      @user.save

      flash[:created_schedule_id] = @schedule.id
      flash[:notice] = 'イベントを作成しました。' unless @user.publicly_visible?
      redirect_to manage_user_schedule_path(@user, @schedule)
    else
      set_copy_schedules
      @btn_name = "新規作成"
      render "new"
    end

  end

	def update
		@schedule = @user.schedules.find(params[:id])

    if @schedule.name_schedules.where(answer: 1).size > schedule_params[:recruitment_numbers].to_i && schedule_params[:recruitment_numbers].to_i != 0
      @schedule.assign_attributes(schedule_params)
      @schedule.errors.add(:recruitment_numbers, 'は現在の参加人数以上に設定してください')
      render "edit"

    else
      if @schedule.update(schedule_params)

        @user.user_time = Time.now
        @user.save

        flash[:notice] = 'イベントを更新しました。'
        redirect_to manage_user_schedule_path(@user, @schedule)
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
    set_meta_tags canonical: "https://circle-book.com#{user_schedule_path(@user, @schedule)}"

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
		@schedule = @user.schedules.find(params[:id])
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
  if params[:date].present?
    raise ActiveRecord::RecordNotFound unless params[:date].is_a?(String) && params[:date].match?(/\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/)
    begin
      date = Date.iso8601(params[:date])
    rescue Date::Error
      raise ActiveRecord::RecordNotFound
    end
    raise ActiveRecord::RecordNotFound unless (1900..2100).cover?(date.year)
    return redirect_to EventSearchPage.path(**event_search_path_options, date: date), status: :moved_permanently
  end
  return if redirect_event_search_url(EventSearchPage.path(**event_search_path_options))
  @day_listing = EventDayListing.new(date: @event_date, event: @event, prefecture: @prefecture, upcoming: true, sort: params[:sort])
  @schedules = @day_listing.schedules.page(params[:page]).per(20)
  @result_count = @day_listing.total_count
  @event_hub_title = EventSearchPage.title(event: @event, prefecture: @prefecture, page: params[:page])
  query = {}
  query[:page] = params[:page].to_i if params[:page].to_i > 1
  @event_hub_path = EventSearchPage.path(**event_search_path_options)
  canonical = 'https://circle-book.com' + @event_hub_path + (query.present? ? '?' + query.to_query : '')
  set_meta_tags title: @event_hub_title,
    description: "#{@prefecture&.name || '全国'}で開催予定の#{EventSearchPage.subject(@event)}を日付から探せます。開催時間・会場・参加費・募集状況を比較し、体験参加や初心者の参加条件は各イベントの詳細で確認できます。",
    canonical: canonical, noindex: @result_count.zero? || %w[2 3].include?(params[:sort]),
    og: { image: 'https://circle-book.com/images/dates.jpg' }
  @b1_name = 'イベント一覧'
  @b1_url = ''
  prepare_event_discovery
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
  render :day unless performed?
end

def tomorrow
  prepare_event_day(Time.current.in_time_zone('Tokyo').to_date + 1, relative: '明日')
  render :day unless performed?
end

def this_week
  start = Time.current.in_time_zone('Tokyo').to_date.beginning_of_week(:monday)
  prepare_event_day(start, relative: '今週', end_date: start + 6)
  render :day unless performed?
end

def next_week
  start = Time.current.in_time_zone('Tokyo').to_date.beginning_of_week(:monday) + 7
  prepare_event_day(start, relative: '来週', end_date: start + 6)
  render :day unless performed?
end

private

  def set_management_schedule
    @schedule = @user.schedules.find(params[:id])
    @b1_name = 'マイページ'
    @b1_url = "/users/#{@user.id}/mypage"
    @b2_name = 'イベント'
    @b2_url = user_schedules_path(@user)
    @b3_name = { 'manage' => @schedule.title.presence || 'イベント管理', 'duplicate' => 'イベントを複製',
      'manage_attendance' => '出欠管理', 'confirm_delete' => '削除の確認' }.fetch(action_name)
    @b3_url = ''
  end

  def private_management_response
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['X-Robots-Tag'] = 'noindex, nofollow'
    response.headers['Referrer-Policy'] = 'same-origin'
  end
  def prepare_event_day(date, relative: nil, end_date: nil)
    period = relative ? action_name : nil
    path = EventSearchPage.path(**event_search_path_options, period: period, date: (date unless relative))
    return if redirect_event_search_url(path)
    @event_date = date
    @date = date.iso8601
    @day = "#{date.year}年#{date.month}月#{date.day}日（#{@wdays[date.wday]}）"
    @relative_day = relative
    @event_end_date = end_date
    @day += "〜#{end_date.year}年#{end_date.month}月#{end_date.day}日（#{@wdays[end_date.wday]}）" if end_date
    @day_listing = EventDayListing.new(date: date, event: @event, prefecture: @prefecture, sort: params[:sort], end_date: end_date)
    @schedules = @day_listing.schedules.page(params[:page]).per(20)
    @result_count = @day_listing.total_count
    @event_day_path = path
    @event_filter_form_path = relative ? "/dates/#{action_name}" : EventDayListing.path(date)
    query = {}
    query[:page] = params[:page].to_i if params[:page].to_i > 1
    @event_day_canonical = 'https://circle-book.com' + @event_day_path
    @event_day_canonical += '?' + query.to_query if query.present?
    @event_day_title = EventSearchPage.title(event: @event, prefecture: @prefecture, period_label: relative || @day, page: params[:page])
    set_meta_tags title: @event_day_title,
      description: "#{relative ? relative + '（' + @day + '）' : @day}に#{@prefecture&.name || '全国'}で開催予定の#{EventSearchPage.subject(@event)}を探せます。開催時間・会場・参加費・募集状況を比較し、参加条件を確認できます。",
      canonical: @event_day_canonical,
      noindex: @result_count.zero? || (end_date || date) < @event_date_today || %w[2 3].include?(params[:sort]),
      og: { title: @event_day_title, url: @event_day_canonical }
    raise ActiveRecord::RecordNotFound if params[:page].to_i > 1 && @schedules.empty?
    @b1_name = 'イベント一覧'
    @b1_url = '/dates'
    @b2_name = @event_day_title
    @b2_url = ''
    prepare_event_discovery
  end

  def prepare_event_search_filters
    @event_date_today = Time.current.in_time_zone('Tokyo').to_date
    @events = Event.where.not(ruby: [nil, '', 'nil']).order(:order).to_a
    @prefectures = Prefecture.where.not(kana: [nil, '', 'nil']).order(:order).to_a
    event_slug = params[:event_slug].presence || params[:event].presence
    prefecture_slug = params[:prefecture_slug].presence || params[:pref].presence
    @event = @events.find { |event| event.ruby == event_slug } if event_slug
    @prefecture = @prefectures.find { |prefecture| prefecture.kana == prefecture_slug } if prefecture_slug
    raise ActiveRecord::RecordNotFound if (event_slug && !@event) || (prefecture_slug && !@prefecture)
    @filter_query = { event: @event&.ruby, pref: @prefecture&.kana }.compact
  end

  def event_search_path_options
    { event: @event&.ruby, prefecture: @prefecture&.kana }
  end

  def redirect_event_search_url(path)
    return false if request.path == path && !request.query_parameters.keys.intersect?(%w[event pref date])
    query = request.query_parameters.select { |key, _| %w[page sort gclid fbclid].include?(key) || key.start_with?('utm_') }
    query.delete('page') if query['page'] == '1'
    redirect_to path + (query.present? ? '?' + query.to_query : ''), status: :moved_permanently
    true
  end

  def prepare_event_discovery
    @event_hub_path = EventSearchPage.path(**event_search_path_options)
    @event_discovery = []
    return if params[:page].to_i > 1
    populations = EventSearchPage.populations(event: @event, prefecture: (@prefecture unless @event))
    if @event
      ids = populations.select { |event_id, _| event_id == @event.id }.map(&:last)
      @event_discovery = @prefectures.select { |prefecture| ids.include?(prefecture.id) }.map do |prefecture|
        ["#{prefecture.name}の#{@event.name}開催予定", EventSearchPage.path(event: @event.ruby, prefecture: prefecture.kana)]
      end
    else
      populations = populations.select { |_, prefecture_id| prefecture_id == @prefecture.id } if @prefecture
      ids = populations.map(&:first)
      @event_discovery = @events.select { |event| ids.include?(event.id) }.map do |event|
        ["#{@prefecture&.name}の#{event.name}開催予定".delete_prefix('の'), EventSearchPage.path(event: event.ruby, prefecture: @prefecture&.kana)]
      end
    end
    @event_discovery.reject! { |_, path| path == @event_hub_path }
    @event_region_discovery = @prefectures.select { |prefecture| populations.any? { |_, id| id == prefecture.id } }.map do |prefecture|
      ["#{prefecture.name}のイベント開催予定", EventSearchPage.path(prefecture: prefecture.kana)]
    end unless @prefecture || @event
  end

  def set_copy_schedules
    @copy_schedules = @user.schedules.order(:day => :asc, :time_s => :asc).last(10)
  end

  def set_copy_schedule
    @copy_schedule = @user.schedules.find(params[:copy]) if params[:copy].present?
  end

  def ensure_schedule_visibility
    return if @user.publicly_visible?

    raise ActiveRecord::RecordNotFound unless can_manage_circle?(@user)

    private_management_response
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
    params.require(:schedule).permit(:day, :venue, :date, :time_s, :time_e, :venue_address, :note, :title, :google_map, :recruitment, :member_venue, :recruitment_numbers, :cost, :top_image, :top_image_cache)
  end

  def name_params
    params.require(:name).permit(:name, :gender, schedule_ids:[], name_schedules_attributes: [:answer, :comment, :schedule_id, :name_id, :_destroy, :id])
  end


end
