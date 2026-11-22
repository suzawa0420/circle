class ScheduleCheckInsController < ActionController::Base
  protect_from_forgery with: :exception
  layout 'schedule_check_in'
  before_action :private_response
  before_action :set_circle
  before_action :set_event, except: :index

  rescue_from ActiveRecord::RecordNotFound do
    @events = []
    render :index, status: :not_found
  end

  def index
    @events = available_events.order(:time_s, :id).to_a
    if @events.one?
      @event = @events.first
      show
    end
  end

  def show
    @multiple_events = available_events.offset(1).exists? if action_name == 'show'
    @answers = eligible_answers.includes(:name).order('names.name', :name_id, :id).to_a.uniq(&:name_id)
    render :show
  end

  def confirm
    @name = selected_answer.name
  end

  def create
    @event.with_lock do
      # Recheck after the lock in case timing or the event changed since the form was shown.
      raise ActiveRecord::RecordNotFound unless @event.day == ScheduleCheckIn.today && @event.recruitment != '中止'

      raise ActiveRecord::RecordNotFound unless @circle.reload.attendance_check_in_token == params[:token]

      answer = selected_answer(lock: true)
      name = answer.name
      @check_in = @event.schedule_check_ins.find_or_create_by!(name_id: name.id) do |check_in|
        check_in.display_name = name.name
        check_in.checked_in_at = Time.current
      end
    end
  end

  private

  def private_response
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['X-Robots-Tag'] = 'noindex, nofollow, noarchive'
    response.headers['Referrer-Policy'] = 'strict-origin'
  end

  def set_circle
    token = params[:token]
    raise ActiveRecord::RecordNotFound unless token.is_a?(String) && token.match?(/\A[A-Za-z0-9_-]{32}\z/)

    @circle = User.find_by!(attendance_check_in_token: token)
  end

  def available_events
    ScheduleCheckIn.accepting(@circle.schedules)
  end

  def set_event
    @event = available_events.find(params[:schedule_id])
  end

  def eligible_answers
    ScheduleCheckIn.eligible_answers(@event)
  end

  def selected_answer(lock: false)
    path = eligible_answers.where(name_id: params.require(:name_id)).order(:id)
    path = path.lock('FOR UPDATE OF name_schedules, names') if lock
    path.first!
  end
end
