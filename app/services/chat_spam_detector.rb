require 'uri'
require 'set'
require 'digest'

class ChatSpamDetector
  THRESHOLD = 5
  REASONS = {
    'adult' => ['成人向け・性的サービスの宣伝表現', 4],
    'sales' => ['予約・料金・派遣などの勧誘表現', 2],
    'contacts' => ['複数の外部リンク・連絡先', 2],
    'hashtags' => ['大量の宣伝ハッシュタグ', 1],
    'repeated' => ['短時間に複数サークルへ同一・類似文を送信', 4],
    'burst' => ['短時間に多数のサークルへ問い合わせ', 1],
    'known_destination' => ['運営がスパムと確認した誘導先', 5]
  }.freeze
  Result = Struct.new(:score, :reasons, :fingerprint, keyword_init: true) do
    def held? = score >= THRESHOLD
  end

  def self.normalized(body)
    body.to_s.unicode_normalize(:nfkc).downcase.gsub(/[[:space:]\p{Cf}]/, '').gsub(/[\p{P}\p{S}]/, '')
  end

  # Match specific destinations, not whole shared services such as Telegram.
  def self.destinations(body)
    body.to_s.unicode_normalize(:nfkc).scan(%r{https?://[^\s<>"'）)]+}i).filter_map do |url|
      uri = URI.parse(url.sub(/[.,!?、。]+\z/, ''))
      next unless uri.host
      "#{uri.host.downcase}#{uri.path.to_s.sub(%r{/+\z}, '')}"
    rescue URI::InvalidURIError
      nil
    end.uniq
  end

  def self.similar?(left, right)
    return false if left.length < 50 || right.length < 50
    return true if left == right
    return false if [left.length, right.length].min.to_f / [left.length, right.length].max < 0.9
    grams = ->(value) { value.chars.each_cons(3).map(&:join).to_set }
    a, b = grams.call(left), grams.call(right)
    (a & b).size.to_f / (a | b).size >= 0.9
  end

  def self.evaluate(conversation, body)
    # Overlong submissions are rejected by ChatMessage; bound moderation work first.
    body = body.to_s.first(2000)
    text = normalized(body)
    reasons = []
    reasons << 'adult' if text.match?(/性愛|性服务|性服務|外送茶|援交|全套服務|全套服务|風俗|性的サービス|sexualservices|escortservice/)
    reasons << 'sales' if text.match?(/予約|料金|派遣|預約|预约|價目|价格|服務|服务|booking|pricelist/)
    links = destinations(body)
    contact_channels = body.to_s.scan(/\b(?:line\s*id|telegram\s*[:：@]|gleezy\s*[:：號号]|tg\s*[:：@])/i).map { |channel| channel.downcase.gsub(/[[:space:]:：@號号]/, '') }.uniq
    reasons << 'contacts' if links.size + contact_channels.size >= 2
    reasons << 'hashtags' if body.to_s.unicode_normalize(:nfkc).scan(/#[\p{L}\p{N}_]+/).size >= 6
    reasons << 'known_destination' if links.any? && ChatSpamDestination.where(destination: links).exists?
    recent = ChatMessage.joins(:conversation).where(conversations: { member_id: conversation.member_id }, sender_role: 'member')
                        .where.not(spam_fingerprint: nil).where('chat_messages.created_at > ?', 30.minutes.ago)
                        .where.not(conversation_id: conversation.id).order(id: :desc).limit(60).pluck(:conversation_id, :body)
    reasons << 'repeated' if recent.select { |_, other_body| similar?(text, normalized(other_body)) }.map(&:first).uniq.size >= 2
    reasons << 'burst' if recent.map(&:first).uniq.size >= 7
    Result.new(score: reasons.sum { |key| REASONS.fetch(key).last }, reasons: reasons, fingerprint: Digest::SHA256.hexdigest(text))
  end
end
