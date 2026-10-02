class DbKeywordsController < ApplicationController
  before_action :webmaster, {except: [:keyword, :kw]}
  before_action :search, {only: [:keyword, :kw]}

  def index
    @db_keywords = DbKeyword.all.order(id: "DESC").page(params[:page])
  end

  def update
    @keyword =  DbKeyword.find(params[:id])
    if @keyword.update(db_keyword_params)
      flash[:notice] = '更新完了！'
      redirect_to db_keywords_path
    else
      flash[:notice] = 'エラー'
      redirect_to db_keywords_path
    end
  end

  def destroy
    @keyword =  DbKeyword.find(params[:id])
    if @keyword.destroy
      flash[:notice] = '削除しました！'
      redirect_to db_keywords_path
    else
      flash[:notice] = 'エラー'
      redirect_to db_keywords_path
    end
	end


  def keyword
    if @keywords = DbKeyword.find_by(keyword: params[:q])

      case params[:q].split(/[[:blank:]]+/).select(&:present?).size

      when 2
        kws = params[:q].split(/[[:blank:]]+/).select(&:present?)
        kws.map do |kw|
          if @kw_event = Event.find_by(name: kw)
          elsif @kw_prefecture = Prefecture.find_by(name: kw)
          elsif @kw_city = City.find_by(name: kw)
          else
          end
        end

        if @kw_event.present? && @kw_prefecture.present?
          redirect_to "/#{@kw_event.ruby}/#{@kw_prefecture.kana}"

        elsif @kw_event.present? && @kw_city.present?
          redirect_to "/#{@kw_event.ruby}/#{@kw_city.prefecture.kana}/#{@kw_city.city_kana}"

        else
        end

      when 1
        if  event = Event.find_by(name: params[:q])
          redirect_to "/#{event.ruby}"

        elsif prefecture = Prefecture.find_by(name: params[:q])
          redirect_to "/prefectures/#{prefecture.kana}"

        elsif city = City.find_by(name: params[:q])
          redirect_to "/prefectures/#{city.prefecture.kana}/#{city.city_kana}"

        else
        end

      else


      end # case

      # Userモデルオブジェクト作成
      @users = User

      # キーワード分割
      @keywords = params[:q].split(/[[:blank:]]+/).select(&:present?)

      # 検索ワードの数だけand検索を行う
      @keywords.each do |keyword|
        @event_ids = Event.where("name LIKE ?", "%#{keyword}%").map { |e| e.id }
        @prefecture_ids = Prefecture.where("name LIKE ?", "%#{keyword}%").map { |p| p.id }

        @city_ids = City.where("name LIKE ?", "%#{keyword}%").map { |c| c.id }
        @city_user_ids = UsersCity.where(city_id: @city_ids).map { |u| u.user_id }
        @tag_ids = Tag.where("name LIKE ?", "%#{keyword}%").map { |t| t.id }
        @tag_user_ids = UserTag.where(tag_id: @tag_ids).map { |u| u.user_id }

        @users = @users.search_word(keyword).
        or(@users.where(event_id: @event_ids)).
        or(@users.where(prefecture_id: @prefecture_ids)).or(@users.where(prefecture_sub_id: @prefecture_ids)).
        or(@users.where(id: @city_user_ids)).
        or(@users.where(id: @tag_user_ids))

      end

      # ソート機能
      if params[:sort] == "1" || params[:sort] == nil
      @users = @users.user_sort_1.page(params[:page])
      elsif params[:sort] == "2"
      @users = @users.user_sort_2.page(params[:page])
      else params[:sort] == "3"
      @users = @users.user_sort_3.page(params[:page])
      end

    else
      flash[:notice] = "URLが間違っています"
      redirect_to circles_path
    end

      # パンくず
      @b1_name = "サークル検索"
      @b1_url = "/users"
      @b2_name = "キーワード一覧"
      @b2_url = "/users/kw"
      @b3_name = "「#{params[:q]}」の検索結果"
      @b3_url = ""
  end

  def kw
    @keywords = DbKeyword.all.order(:search_count => :DESC, :updated_at => :DESC).limit(100)

    # パンくず
    @b1_name = "サークル検索"
    @b1_url = "/users"
    @b2_name = "キーワード一覧"
  end




  private
	def db_keyword_params
		params.require(:db_keyword).permit(:keyword)
	end

  def search
		if admin_user_signed_in?
			@user = current_admin_user.users.first
		end
    @categories = Category.all.order(:id => :asc)
		@events = Event.all.order(:order => :asc)
		@prefectures = Prefecture.all.order(:order => :asc)
  end

  def webmaster
    require_webmaster!
  end
end
