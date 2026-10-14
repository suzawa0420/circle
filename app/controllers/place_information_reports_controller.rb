class PlaceInformationReportsController < ApplicationController
  include HelpSubmission
  before_action :private_help_page
  before_action :set_place

  def new
    @report = @place.place_information_reports.build
  end

  def create
    return unless verify_spam_form!("place-information-report:#{@place.id}")

    @report = @place.place_information_reports.build(params.require(:place_information_report).permit(:kind, :body, :reference_url))
    if @report.save
      accepted
    else
      render :new, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotUnique
    # Double clicks and identical reports on the same day create one inbox item.
    accepted
  end

  private

  def set_place
    @place = Place.includes(:prefecture, :city, :events).find(params[:place_id])
  end

  def accepted
    redirect_to "#{helpers.place_listing_path(@place)}#place-information-report", status: :see_other,
      notice: '修正依頼を受け付けました。運営で内容を確認します。'
  end
end
