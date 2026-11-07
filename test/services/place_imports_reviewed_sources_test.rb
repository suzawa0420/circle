require 'test_helper'

class PlaceImportsReviewedSourcesTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  test 'registry has stable unique reviewed keys and rejects arbitrary source names' do
    sources = PlaceImports::ReviewedSources.all
    assert_equal sources.size, sources.map(&:key).uniq.size
    assert_includes sources.map(&:key), 'mizuno_nationwide'
    sources.each { |source| assert_equal source.key, PlaceImports::ReviewedSources.fetch(source.key).key }
    %w[unknown https://unreviewed.example Kernel].each do |key|
      assert_raises(ArgumentError) { PlaceImports::ReviewedSources.fetch(key) }
    end
  end
end
