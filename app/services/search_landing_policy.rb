require 'digest'
require 'json'
require 'set'

# Preserve search landings with observed Google clicks (2026-08-06..09-30).
# Hashes avoid committing the actual query strings. New arbitrary internal
# searches remain usable, but are not new indexable landing pages.
class SearchLandingPolicy
  HASHES = JSON.parse(Rails.root.join('config/seo_search_landing_hashes.json').read).to_set.freeze

  def self.indexable?(query)
    HASHES.include?(Digest::SHA256.hexdigest(query.to_s))
  end
end
