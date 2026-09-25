require 'digest'

# Only the public keyword search opts in. Never cache records or authorization.
# Per-process bounded storage avoids new infrastructure and unbounded disk keys.
module SearchResultCountCache
  STORE = ActiveSupport::Cache::MemoryStore.new(size: 4.megabytes)
  TTL = 30.seconds

  module RelationMethods
    def total_count(column_name = :all, options = nil)
      return super unless column_name == :all && options.nil? &&
        group_values.empty? && select_values.empty? && !distinct_value && !max_pages

      # Keep all predicates; ordering and page do not affect the exact count.
      sql = except(:order, :limit, :offset, :includes, :preload).to_sql
      key = "public-search-count-v1:#{Digest::SHA256.hexdigest(sql)}"
      SearchResultCountCache::STORE.fetch(key, expires_in: SearchResultCountCache::TTL) { super }
    end
  end
end
