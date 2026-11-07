module PlaceImports
  # Reviewed 2026-11-07 from the operator's separate venue pages:
  # https://www.kc-sports.or.jp/facilities/f300/f305/ (outdoor tennis)
  # https://www.kc-sports.or.jp/facilities/f300/ (shared reservation office)
  # This is an identity review, not a general exemption for shared telephones.
  module ReviewedDistinctVenues
    SOURCE = 'kochi_sports'.freeze
    URL = 'https://www.kc-sports.or.jp/facilities/f300/f305/'.freeze
    INDOOR_VENUES = {
      'くろしおアリーナ体育館' => '高知県高知市五台山1736',
      '高知市東部総合運動場体育センター' => '高知県高知市五台山1736-1'
    }.freeze

    def self.phone_only_overlap_reviewed?(source:, source_url:, data:, name:, address:, tag:)
      return false unless source == SOURCE && source_url == URL && data['url'] == URL
      return false unless data['name'] == '東部総合運動場テニスコート' && data['prefecture'] == '高知県'
      return false unless data['tag'] == '2' && data['sports'] == ['テニス'] && tag == '1'
      return false unless data['tel'].to_s.unicode_normalize(:nfkc).gsub(/\D/, '') == '0888781150'
      return false unless Registrar.normalize(data['address']) == Registrar.normalize('高知県高知市介良1221-1')
      expected = INDOOR_VENUES[name]
      expected.present? && Registrar.normalize(address) == Registrar.normalize(expected)
    end
  end
end
