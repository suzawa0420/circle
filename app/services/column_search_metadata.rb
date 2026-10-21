class ColumnSearchMetadata
  PROFILES = YAML.safe_load_file(Rails.root.join('config/column_seo.yml')).fetch('articles').freeze

  def self.for(column)
    profile = PROFILES[column.id]
    profile = nil unless profile && profile['heading'] == column.title
    body = ActionView::Base.full_sanitizer.sanitize(column.text.to_s).gsub(/\[商品:\d+\]/, '').squish
    {
      title: profile ? profile.fetch('title') : column.title,
      description: profile ? profile.fetch('description') : (column.description.presence || body.truncate(150))
    }
  end
end
