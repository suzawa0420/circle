require 'uri'
require 'set'
require 'digest'

class ChatSpamDetector
  THRESHOLD = 5
  REASONS = {
    'adult' => ['成人向け・性的サービスの宣伝表現', 4],
    'sales' => ['予約・料金・派遣などの勧誘表現', 2],
    'solicitation' => ['取材・記事掲載・サービス紹介の勧誘', 5],
    'business_offer' => ['集客支援・制作・広告サービスの営業提案', 5],
    'financial_pitch' => ['副業・投資・収入をうたう勧誘', 5],
    'external_invitation' => ['外部連絡先への登録・詳細案内の誘導', 3],
    'contacts' => ['複数の外部リンク・連絡先', 2],
    'hashtags' => ['大量の宣伝ハッシュタグ', 1],
    'repeated' => ['短時間に複数サークルへ同一・類似文を送信', 4],
    'shared_destination' => ['短時間に複数サークルへ同じ誘導先を送信', 2],
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
    # Require an offer/request, rather than an occupation, topic, identity or URL.
    reasons << 'solicitation' if solicitation?(text)
    reasons << 'business_offer' if business_offer?(text)
    reasons << 'financial_pitch' if financial_pitch?(text)
    reasons << 'external_invitation' if external_invitation?(text)
    links = destinations(body)
    contact_channels = body.to_s.scan(/\b(?:line\s*id|telegram\s*[:：@]|gleezy\s*[:：號号]|tg\s*[:：@])/i).map { |channel| channel.downcase.gsub(/[[:space:]:：@號号]/, '') }.uniq
    reasons << 'contacts' if links.size + contact_channels.size >= 2
    reasons << 'hashtags' if body.to_s.unicode_normalize(:nfkc).scan(/#[\p{L}\p{N}_]+/).size >= 6
    reasons << 'known_destination' if links.any? && ChatSpamDestination.where(destination: links).exists?
    sender_scope = conversation.practice_match? ? { source_user_id: conversation.source_user.admin_user.users.select(:id) } : { member_id: conversation.member_id }
    recent = ChatMessage.joins(:conversation).where(conversations: sender_scope, sender_role: 'member')
                        .where.not(spam_fingerprint: nil).where('chat_messages.created_at > ?', 30.minutes.ago)
                        .where.not(conversations: { user_id: conversation.user_id }).order(id: :desc).limit(60).pluck('conversations.user_id', :body)
    current_campaign_text = campaign_text(body)
    reasons << 'repeated' if recent.select { |_, other_body| similar?(current_campaign_text, campaign_text(other_body)) }.map(&:first).uniq.size >= 2
    if links.any?
      recent_links = recent.map { |circle_id, other_body| [circle_id, destinations(other_body)] }
      reasons << 'shared_destination' if links.any? { |link| recent_links.select { |_, other_links| other_links.include?(link) }.map(&:first).uniq.size >= 2 }
    end
    reasons << 'burst' if recent.map(&:first).uniq.size >= 7
    Result.new(score: reasons.sum { |key| REASONS.fetch(key).last }, reasons: reasons, fingerprint: Digest::SHA256.hexdigest(text))
  end

  def self.solicitation?(text)
    text.match?(/(?:取材|インタビュー|ヒアリング)(?:させて|をさせて|をお願い|のお願い|のご依頼|の依頼|のご相談|の相談)/) ||
      text.match?(/(?:記事|メディア|サイト|媒体).{0,60}(?:紹介|掲載)(?:できれば|できたら|させて|しませんか|したく|したい|いたします|のご相談|のお願い)/) ||
      text.match?(/(?:記事|メディア|媒体).{0,60}(?:お話|話).{0,10}(?:伺いたい|伺えませんか|聞かせて)/) ||
      text.match?(/(?:弊社|当社|弊サービス).{0,60}(?:サービス|商品|製品).{0,30}(?:ご紹介|ご案内|ご提案)/)
  end

  def self.business_offer?(text)
    text.match?(/(?:集客支援|集客サービス|集客サポート|ホームページ制作|ホームページ作成|web制作|ウェブ制作|seo対策|広告運用).{0,40}(?:ご提案|ご案内|ご紹介|導入しませんか|導入をご検討|お手伝いさせて)/) ||
      text.match?(/(?:ご提案|ご案内|ご紹介).{0,20}(?:する|したい|させて|です).{0,20}(?:集客支援|ホームページ制作|seo対策|広告運用)/)
  end

  def self.financial_pitch?(text)
    text.match?(/(?:副収入|不労所得|副業|資産運用|投資案件|投資セミナー|ネットワークビジネス|マルチ商法).{0,40}(?:説明会|ご招待|稼げる|稼ぎませんか|稼ぎたい方|収入を増や|セミナーに参加しませんか)/) ||
      text.match?(/(?:説明会|セミナー).{0,30}(?:副収入|不労所得|副業|資産運用|投資案件).{0,30}(?:ご招待|稼げる|ご案内)/)
  end

  def self.external_invitation?(text)
    text.match?(/(?:line|ライン|オープンチャット|telegram|テレグラム).{0,20}(?:追加|登録|参加).{0,30}(?:詳しくはこちら|詳細はこちら|登録してください|登録をお願い|詳細をご案内)/) ||
      text.match?(/(?:詳しくはこちら|詳細はこちら|詳細をご案内).{0,30}(?:line|ライン|オープンチャット|telegram|テレグラム).{0,20}(?:追加|登録|参加)/)
  end

  # Ignore only a short addressee line; retain the actual message for scoring.
  def self.campaign_text(body)
    normalized(body.to_s.unicode_normalize(:nfkc).sub(/\A[[:blank:]]*[^\r\n。！？!?]{1,40}(?:様|さま|さん)[[:blank:]、,:：]*\r?\n/, ''))
  end
end
