module PublicSearchSeo
  extend ActiveSupport::Concern

  included do
    helper_method :public_search_listing?
    before_action :validate_public_search_parameters
    before_action :set_public_search_metadata
  end

  def public_search_listing?
    return true if controller_path == 'circles/circles' && action_name == 'index'
    return true if controller_path == 'circles/search' && %w[index show].include?(action_name)
    return true if controller_path.start_with?('circles/events/', 'circles/prefectures/', 'circles/tags/') && action_name == 'show'
    return true if controller_path == 'tags' && %w[event event_prefecture event_prefecture_city prefecture prefecture_city].include?(action_name)
    false
  end

  # Prepare the bounded relation before both JSON-LD and HTML render it. Previously
  # the markup and size check eagerly loaded reviews/tags and repeated the query.
  def default_render(*args)
    if public_search_listing? && @users.respond_to?(:preload)
      @listing_data ||= CircleListingData.new(@users)
      @users = @listing_data.users
      if @users.to_a.empty?
        raise ActiveRecord::RecordNotFound if params[:page].to_i > 1
        set_meta_tags noindex: true
      end
    elsif controller_path == 'schedules' && action_name == 'day' && @schedules
      if @schedules.empty?
        raise ActiveRecord::RecordNotFound if params[:page].to_i > 1
        set_meta_tags noindex: true
      end
    end
    super
  end

  private

  def validate_public_search_parameters
    return unless public_search_listing? || (controller_path == 'schedules' && action_name == 'day')
    if params.key?(:page)
      value = params[:page].to_s
      raise ActiveRecord::RecordNotFound unless value.match?(/\A[1-9]\d{0,4}\z/)
    end
    if params.key?(:sort)
      raise ActiveRecord::RecordNotFound unless %w[1 2 3].include?(params[:sort])
    end
  end

  def set_public_search_metadata
    return unless public_search_listing? || (controller_path == 'schedules' && action_name == 'day') ||
                  (controller_path == 'circles/circles' && action_name == 'show')
    query = request.query_parameters.reject do |key, _|
      key == 'sort' || key.start_with?('utm_') || %w[gclid fbclid].include?(key)
    end
    query.delete('page') if query['page'] == '1'
    url = 'https://circle-book.com' + request.path
    url += '?' + query.to_query if query.present?
    set_meta_tags canonical: url
    if controller_path == 'circles/search' && !SearchLandingPolicy.indexable?(params[:q])
      set_meta_tags noindex: true
    end
  end
end
