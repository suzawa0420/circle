class Circles::SearchController < Circles::ApplicationController
  before_action :set_search, only: [:index, :show, :landing]


	def index
    params[:q] = params[:q].to_s.gsub("　"," ")

    if (landing = CircleFilterLanding.from_search(params))
      query = params.permit(:sort, :page).to_h
      landing += "?#{query.to_query}" if query.present?
      return redirect_to landing, status: :see_other
    end

    if detailed_search?
      set_keyword_search
    elsif params[:q] == nil || params[:q] == ""
      redirect_to circles_path

    elsif DbKeyword.find_by(keyword: params[:q])
      redirect_to circles_search_path(params[:q])
    else
      set_keyword_search

      # 検索ワードの保存
      # 各キーワードを半角で保存
      @keywords.map.with_index(1){|kw,i|
        if i == 1
          @sort_kw = "#{@sort_kw}" + "#{kw}"
        else
          # 2個目以降は間に半角スペース
          @sort_kw = "#{@sort_kw}" + " #{kw}"
        end
      }
      if DbKeyword.find_by(keyword: @sort_kw) || params[:q].count("^ ") <= 1 || !@users.exists?
      else
        @db_keyword = DbKeyword.new
        @db_keyword.keyword = @sort_kw
        @db_keyword.save
      end

      # 既存と同じキーワードの場合カウント+1
      if @kw = DbKeyword.find_by(keyword: @sort_kw)
        @kw.increment!(:search_count, 1)
      end
    end


  end


  def show
    if DbKeyword.find_by(keyword: params[:q])
      set_keyword_search
    else
      redirect_to circles_path
    end
  end



  def landing
    # Path dimensions define this page; query filters cannot override them.
    extra = request.query_parameters.keys - %w[sort page utm_source utm_medium utm_campaign utm_term utm_content gclid fbclid]
    if extra.any?
      query = params.permit(:sort, :page).to_h
      url = request.path
      url += "?#{query.to_query}" if query.present?
      return redirect_to url, status: :moved_permanently
    end
    event = params[:activity] == 'all' ? nil : Event.find_by!(ruby: params[:activity])
    prefecture = params[:region] == 'all' ? nil : Prefecture.find_by!(kana: params[:region])
    group = params[:group] == 'all' ? nil : Group.find(params[:group])
    age = params[:age] == 'all' ? nil : Age.find(params[:age])
    unless group || age
      return redirect_to CircleFilterLanding.path(event: event, prefecture: prefecture), status: :moved_permanently
    end
    @landing_filters = { detailed: '1', q: '', event_id: event&.id, prefecture_id: prefecture&.id,
      group_ids: group ? [group.id.to_s] : [], age_ids: age ? [age.id.to_s] : [] }
    @filtered_landing = true
    set_keyword_search
    if @users.to_a.empty?
      raise ActiveRecord::RecordNotFound if params[:page].to_i > 1
      set_meta_tags noindex: true
    end
    render :index
  end

private
  def detailed_search?
    @filtered_landing || params[:detailed] == '1'
  end

  def apply_detailed_filters(users)
    return users unless detailed_search?

    filters = @landing_filters || params
    @event = Event.find(filters[:event_id]) if filters[:event_id].present?
    @prefecture = Prefecture.find(filters[:prefecture_id]) if filters[:prefecture_id].present?
    users = users.where(event_id: @event.id) if @event
    users = users.where_pref(@prefecture.id) if @prefecture
    @category = Category.find(filters[:category_id]) if filters[:category_id].present?
    users = users.where(category_id: @category.id) if @category
    @city = City.find(filters[:city_id]) if filters[:city_id].present?
    users = users.where_city(@city) if @city
    @tag = Tag.find(filters[:tag_id]) if filters[:tag_id].present?
    users = users.where(id: UserTag.where(tag_id: @tag.id).select(:user_id)) if @tag

    group_ids = Array(filters[:group_ids]).reject(&:blank?)
    age_ids = Array(filters[:age_ids]).reject(&:blank?)
    @search_groups = Group.where(id: group_ids).order(:id).to_a
    @search_ages = Age.where(id: age_ids).order(:id).to_a
    users = users.where(id: UsersGroup.where(group_id: group_ids).select(:user_id)) if group_ids.any?
    users = users.where(id: UsersAge.where(age_id: age_ids).select(:user_id)) if age_ids.any?
    users
  end

  def set_keyword_search
      # Userモデルオブジェクト作成
      users = User.publicly_visible

      # キーワード分割
      @keywords = (@landing_filters || params)[:q].to_s.split(/[[:blank:]]+/).select(&:present?)

      # 検索ワードの数だけand検索を行う
      @keywords.each do |keyword|
        event_ids = Event.where("name LIKE ?", "%#{keyword}%").select(:id)
        prefecture_ids = Prefecture.where("name LIKE ?", "%#{keyword}%").select(:id)

        city_ids = City.where("name LIKE ?", "%#{keyword}%").select(:id)
        city_user_ids = UsersCity.where(city_id: city_ids).select(:user_id)

        tag_ids = Tag.where("name LIKE ?", "%#{keyword}%").select(:id)
        tag_user_ids = UserTag.where(tag_id: tag_ids).select(:user_id)

        users = users.search_word(keyword).
        or(users.where(event_id: event_ids)).
        or(users.where(prefecture_id: prefecture_ids)).or(users.where(prefecture_sub_id: prefecture_ids)).
        or(users.where(id: city_user_ids)).
        or(users.where(id: tag_user_ids))
      end

      users = apply_detailed_filters(users).list

      case params[:sort]
      when "1", nil
        @users = users.sort_1.page(params[:page])
      when "2"
        @users = users.sort_2.page(params[:page])
      when "3"
        @users = users.sort_3.page(params[:page])
      end

      # The empty-state check and partial must share this bounded relation.
      # Calling size first would run the expensive search again as COUNT.
      if @users
        @listing_data = CircleListingData.new(@users)
        @users = @listing_data.users
      end
  end

end
