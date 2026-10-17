module CircleDiscoveryHelper
  # Keep each link on an existing, populated landing. Do not silently discard a
  # city, tag or keyword: those dimensions have different search populations.
  def circle_audience_links
    return [] if @city || @tag
    return [] if controller_path == 'circles/search' && !@filtered_landing

    group = Array(@search_groups).first
    age = Array(@search_ages).first
    users = User.publicly_visible.where(switch: '募集中')
    users = users.for_event(@event.id) if @event
    users = users.where_pref(@prefecture.id) if @prefecture
    users = users.where(id: UsersGroup.where(group_id: group.id).select(:user_id)) if group
    users = users.where(id: UsersAge.where(age_id: age.id).select(:user_id)) if age

    links = []
    if !group && (social = Group.find_by(name: '社会人'))
      if users.where(id: UsersGroup.where(group_id: social.id).select(:user_id)).exists?
        links << circle_audience_link(group: social, age: age)
      end
    end
    unless age
      ages = Age.where(id: UsersAge.where(user_id: users.select(:id)).select(:age_id)).order(:decade, :id)
      ages.each { |item| links << circle_audience_link(group: group, age: item) }
    end
    links
  end

  # A legacy tag remains a separate, indexable page. Offer a clearly named
  # audience alternative instead of claiming both taxonomies are equivalent.
  def circle_tag_audience_link
    return unless @tag && !@city
    age = Age.find_by(name: @tag.name)
    social = Group.find_by(name: '社会人')
    return unless age && social
    users = User.publicly_visible.where(switch: '募集中')
    users = users.for_event(@event.id) if @event
    users = users.where_pref(@prefecture.id) if @prefecture
    return unless users.where(id: UsersAge.where(age_id: age.id).select(:user_id))
      .where(id: UsersGroup.where(group_id: social.id).select(:user_id)).exists?
    circle_audience_link(group: social, age: age)
  end

  private

  def circle_audience_link(group:, age:)
    area = @prefecture ? "#{@prefecture.name}の" : '全国の'
    activity = @event ? "#{@event.name}サークル" : 'サークル'
    audience = [group&.name, age&.name].compact.join('・')
    { label: "#{area}#{audience}向け#{activity}",
      path: CircleFilterLanding.path(event: @event, prefecture: @prefecture, group: group, age: age) }
  end
end
