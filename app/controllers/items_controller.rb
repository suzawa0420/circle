class ItemsController < ApplicationController

before_action :ensure_correct_user
before_action :set_items


	def index
	end

	def new
	end

	def create
		@collection.items.create(item_params)

		if @collection.save

			flash[:notice] = "追加しました"
			redirect_to user_collection_path(@user.id, @collection.id)

		else
			flash[:notice] = "エラーです"
			redirect_to user_collection_path(@user.id, @collection.id)
		end


	end

	def show
	end

	def edit
	end

	def update
		@item = Item.find(params[:id])

		if  params[:check] == "check" || params[:check] == ""

			@item.check = params[:check]
			@item.update(check: params[:check])
			redirect_to user_collection_path(@user, @collection)

		else
			flash[:notice] = "不正なデータです"
			redirect_to user_collection_path(@user, @collection)			
		end

	end

	def destroy
		@item = Item.find(params[:id])
		@item.destroy
		flash[:notice] = "削除しました"
		redirect_to user_collection_path(@user, @collection)
	end


	private
		def item_params
			params.require(:item).permit(:name, :money, :check)
		end

		def set_items
			@collection = Collection.find_by(id: params[:collection_id])
			@user = User.find_by(id: @collection.user_id)
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

end
