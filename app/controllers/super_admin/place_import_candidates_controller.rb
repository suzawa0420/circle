class SuperAdmin::PlaceImportCandidatesController < ApplicationController
  before_action :require_webmaster!

  def index
    @status = PlaceImportCandidate::STATUSES.key?(params[:status]) ? params[:status] : 'pending'
    @candidates = PlaceImportCandidate.where(status: @status).order(updated_at: :desc, id: :desc).page(params[:page]).per(30)
    @runs = PlaceImportRun.order(id: :desc).limit(10)
  end

  def show
    @candidate = PlaceImportCandidate.find(params[:id])
  end

  def update
    @candidate = PlaceImportCandidate.find(params[:id])
    case params[:decision]
    when 'dismiss'
      @candidate.with_lock do
        @candidate.update!(status: 'dismissed', reason: '管理者が見送りました') unless @candidate.status == 'registered'
      end
    when 'register'
      PlaceImports::Registrar.new.call(@candidate, apply: true)
    else
      return head :unprocessable_entity
    end
    redirect_to super_admin_place_import_candidate_path(@candidate), notice: @candidate.reload.reason
  end
end
