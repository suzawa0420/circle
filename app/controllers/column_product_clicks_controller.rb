class ColumnProductClicksController < ApplicationController
  skip_before_action :set_imperfect_current_user

  def create
    response.headers['Cache-Control'] = 'no-store'
    return head :no_content if webmaster?
    return head :unprocessable_entity unless %w[amazon mercari].include?(params[:shop])

    product = ColumnProduct.joins(:column).merge(Column.published).find_by!(id: params[:id], column_id: params[:column_id])
    return head :unprocessable_entity if product.public_send("#{params[:shop]}_url").blank?

    product.increment!("#{params[:shop]}_clicks")
    head :no_content
  end
end
