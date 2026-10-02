class ColumnsController < ApplicationController
  before_action :set_column
  before_action :require_webmaster!, only: [:new, :create, :edit, :update, :destroy]


  def index
    @columns = Column.all.order(created_at: "DESC")
  end 

  def new
    @column = Column.new
  end

  def create
    @column = Column.new(column_params)

    if @column.update(column_params)
      redirect_to column_path(@column.id)
    else
      render "/columns/edit"
    end 

  end

  def show
    @column = Column.find(params[:id])
  end



  def edit
    @column = Column.find(params[:id])
    @column_button = "編集する"
  end

  def update
    @column = Column.find(params[:id])

    if @column.update(column_params)
      redirect_to column_path
    else
      render "/columns/edit"
    end 
  end

  def destroy
      @column = Column.find(params[:id])
      @column.destroy   

    redirect_to("/")
  end


    def set_column
      @columns = Column.all.order(created_at: "DESC")

    if admin_user_signed_in?
      @current_user = User.find_by(id: current_admin_user.id)
    end

    end


  private
  def column_params
    params.require(:column).permit(
      :title, 
      :text,
      :description,
      :image
    )
  end





end
