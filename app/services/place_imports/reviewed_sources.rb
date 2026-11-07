module PlaceImports
  # Only reviewed, permissioned adapters belong here. This is not a domain crawler.
  module ReviewedSources
    def self.all
      [MizunoSource.new, SapporoSource.new, SendaiSource.new]
    end

    def self.fetch(key)
      all.find { |source| source.key == key } || raise(ArgumentError, 'unreviewed source')
    end
  end
end
