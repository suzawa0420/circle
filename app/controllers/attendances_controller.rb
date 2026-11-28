class AttendancesController < ApplicationController

include Circlebook

before_action :set_attendances

	def index
    # Never cache an organizer's response where a participant could receive it.
    @schedule_share_allowed = admin_user_signed_in? && current_admin_user.id == @user&.admin_user_id
    archive = params[:archive] == "1"
    @show_check_in_history = archive && can_manage_circle?(@user)
    response.headers["Cache-Control"] = "private, no-store" if @schedule_share_allowed || @show_check_in_history

    now = Time.current.in_time_zone('Tokyo')
    today = now.to_date.iso8601
    circle_schedules = @user.schedules
    finished_today = circle_schedules.where(day: today).where.not(time_e: nil)
      .select(:id, :day, :time_s, :time_e).select { |schedule| schedule.attendance_finished?(now) }
    past = circle_schedules.where("day < ?", today).or(circle_schedules.where(id: finished_today.map(&:id)))
    @past_schedules = past.order(day: :desc, time_s: :asc).page(params[:page])
    @schedules = if archive
      past.order(day: :desc, time_s: :desc, id: :desc).limit(5)
    else
      circle_schedules.where("day >= ?", today).order(day: :asc, time_s: :asc)
    end

    @name = Name.new
    @name_schedules = @name.name_schedules.build
    @today = DateTime.yesterday

    schedule_ids = @schedules.map(&:id)
    answers = NameSchedule.where(schedule_id: schedule_ids).where.not(answer: nil).order(:id).to_a
    @answers_by_schedule_and_name = answers.group_by(&:schedule_id).transform_values do |rows|
      rows.reverse.index_by(&:name_id)
    end
    name_ids = answers.map(&:name_id)
    @check_ins_by_schedule = {}
    if @show_check_in_history
      check_ins = ScheduleCheckIn.where(schedule_id: schedule_ids).order(:checked_in_at, :id).to_a
      @check_ins_by_schedule = check_ins.group_by(&:schedule_id).transform_values { |rows| rows.index_by(&:name_id) }
      name_ids.concat(check_ins.map(&:name_id))
    end
    @names = Name.where(id: name_ids).order(updated_at: :desc).to_a
    if @show_check_in_history
      current_name_ids = @names.map(&:id).to_set
      check_ins.reverse.uniq(&:name_id).each do |record|
        next if current_name_ids.include?(record.name_id)

        @names << Name.new(id: record.name_id, name: record.display_name)
      end
    end
  end

  def new
    @name = Name.new
    @name_schedules = @name.name_schedules.build
    @schedules = Schedule.where(user_id: @user.id).where("day > ?", DateTime.yesterday).order(:day => :asc, :time_s => :asc)


    # 空きがあるかチェック
    # full_schedules = @schedules.select do |schedule|
    #   schedule.name_schedules.where(answer: 1).size < schedule.recruitment_numbers && schedule.recruitment_numbers != 0
    # end

    # if full_schedules.present?
    #   flash[:notice] = "登録できる日程がありません"
    #   redirect_to attendances_path(@user.unique_id) and return
    # end


  end

	def create
    @name = Name.new(name_params)
    @schedules = Schedule.where(user_id: @user.id).where("day > ?", DateTime.yesterday).order(:day => :asc, :time_s => :asc)

    if name_params[:name_schedules_attributes].present?
      schedule_ids = name_params[:name_schedules_attributes].values.map { |params| params[:schedule_id] if params[:answer] == "1" }.compact
      schedules = Schedule.where(id: schedule_ids)
    else
      flash[:notice] = "登録できる日程がありません"
      redirect_to attendances_path(@user.unique_id) and return
    end

    # 既に満員のスケジュールがあるかチェック
    full_schedules = schedules.select do |schedule|
      # 全条件TRUEが1個でもあれば満員の日程あり
      schedule.recruitment_numbers.present? && schedule.name_schedules.where(answer: 1).size >= schedule.recruitment_numbers && schedule.recruitment_numbers != 0
    end

    if full_schedules.present?
      flash[:notice] = "既に満員の日程があります"
      redirect_to new_attendance_path(@user.unique_id) and return
    end


    if @name.save
      flash[:notice] = "追加しました"
      redirect_to attendances_path(@user.unique_id)
    else
      flash[:notice] = "エラー"
      render "new"
    end

  end


	def edit
    @name = Name.find(params[:id])
    @schedules = Schedule.where(user_id: @user.id).where("day > ?", DateTime.yesterday).order(:day => :asc, :time_s => :asc)
	end

	def update
    @name = Name.find(params[:id])
    @name.updated_at = Time.now
    @schedules = Schedule.where(user_id: @user.id).where("day > ?", DateTime.yesterday).order(:day => :asc, :time_s => :asc)

    schedule_ids = name_params[:name_schedules_attributes].values.map { |params| params[:schedule_id] if params[:answer] == "1" }.compact
    schedules = Schedule.where(id: schedule_ids)

    # 既に満員のスケジュールがあるかチェック
    full_schedules = schedules.select do |schedule|
      schedule.recruitment_numbers.present? && schedule.recruitment_numbers != 0 &&
        schedule.name_schedules.where(answer: 1).where.not(name_id: @name.id).count >= schedule.recruitment_numbers
    end

    if full_schedules.present?
      flash[:notice] = "既に満員の日程があります"
      redirect_to edit_attendance_path(@user.unique_id, @name.id) and return
    end


    # @name.update(name_params)
    # @name.updated_at = Time.now

    if @name.update(name_params)
      flash[:notice] = "更新しました"
      redirect_to attendances_path(@user.unique_id)
    else
      flash[:notice] = "エラー"
      render "edit"
    end
	end

	def destroy
    @name = Name.find(params[:id])
    @name.destroy

    flash[:notice] = "削除しました"
    redirect_to attendances_path(@user.unique_id)
	end






private
  def set_attendances
    @user = User.find_by(unique_id: params[:unique_id])
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
