class ColumnsController < ApplicationController
  layout -> { action_name == 'show' ? 'application' : account_layout }
  before_action :require_webmaster!, except: [:index, :show]
  before_action :find_column, only: [:show, :edit, :update, :destroy]
  before_action :prepare_editor, only: [:new, :create, :edit, :update]

  def index
    @columns = webmaster? ? Column.all : Column.published
    @columns = @columns.where(audience: params[:audience]) if Column::AUDIENCES.key?(params[:audience])
    @columns = @columns.includes(:event).order(updated_at: :desc, id: :desc).page(params[:page]).per(20)
  end

  def new
    @column = Column.new(publication_status: 'draft', affiliate: true)
  end

  def create
    @column = Column.new(column_params)
    save_column(:new)
  end

  def show
    @preview = webmaster?
    set_meta_tags noindex: true if @preview
  end

  def edit; end

  def update
    @column.assign_attributes(column_params)
    save_column(:edit)
  end

  def destroy
    @column.destroy!
    redirect_to columns_path, notice: '記事を削除しました。', status: :see_other
  end

  private

  def find_column
    @column = (webmaster? ? Column.all : Column.published).includes(:column_products, :event).find(params[:id])
  end

  def prepare_editor
    @events = Event.order(:order, :id)
  end

  def save_column(template)
    @column.publication_status = params[:intent] == 'publish' ? 'published' : 'draft'
    if @column.save
      redirect_to edit_column_path(@column), notice: @column.published? ? '記事を公開しました。' : '下書きを保存しました。', status: :see_other
    else
      render template, status: :unprocessable_entity
    end
  end

  def column_params
    params.require(:column).permit(:title, :text, :description, :image, :image_cache, :remove_image,
      :audience, :event_id, :affiliate,
      column_products_attributes: [:id, :name, :description, :amazon_url, :image_url, :position, :_destroy])
  end
end
