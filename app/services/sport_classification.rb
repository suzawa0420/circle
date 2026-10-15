# Suggestions only. A name/body mention is not evidence that a club runs a sport.
class SportClassification
  SPORTS = {
    'karate' => ['空手'],
    'handicraft' => ['手芸', 'ハンドメイド', '編み物'],
    'karaoke' => ['カラオケ'],
    'soft-tennis' => ['ソフトテニス', '軟式テニス'],
    'pickleball' => ['ピックルボール'],
    'ski' => ['スキー'],
    'surfing' => ['サーフィン']
  }.freeze

  def self.candidates(slug)
    words = SPORTS.fetch(slug)
    base = User.publicly_visible
    matches = words.map do |word|
      base.where("users.name LIKE :word OR users.recruitment LIKE :word OR users.appeal LIKE :word", word: "%#{word}%")
    end.reduce(&:or)
    sport = Event.find_by(ruby: slug)
    matches = matches.where.not(id: User.for_event(sport.id).select(:id)) if sport
    matches
  end
end
