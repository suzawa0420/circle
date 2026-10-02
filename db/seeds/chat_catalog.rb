# Import the production catalog into the isolated demo DB without replacing IDs
# already referenced by local circles, bookmarks or participant interests.
raise 'This seed requires the isolated local chat database' unless Rails.env.development? && ActiveRecord::Base.connection_db_config.database == 'circle_chat_development'

ActiveRecord::Base.transaction do
  [[Category, :kana, 'chat-demo', 'ball-sports'], [Event, :ruby, 'chat-demo-basketball', 'basketball'], [Prefecture, :kana, 'chat-demo-tokyo', 'tokyo']].each do |model, key, old, current|
    model.find_by(key => old)&.update!(key => current) unless model.exists?(key => current)
  end
  category_ids = {}
  [Category, Event, Prefecture].each do |model|
    rows = []
    collector = Module.new
    receiver = Object.new
    receiver.define_singleton_method(:seed) { |_key, *values| rows.concat(values) }
    collector.const_set(model.name, receiver)
    path = Rails.root.join('db', 'fixtures', "#{model.name.underscore}.rb")
    collector.module_eval(File.read(path), path.to_s)
    key = model == Event ? :ruby : :kana
    rows.each do |row|
      attrs = row.except(:id)
      attrs[:category_id] = category_ids.fetch(row[:category_id]) if model == Event
      record = model.find_or_initialize_by(key => row.fetch(key))
      record.update!(attrs)
      category_ids[row[:id]] = record.id if model == Category
    end
  end
end
puts "Local catalog ready: #{Event.count} interests, #{Prefecture.count} areas"
