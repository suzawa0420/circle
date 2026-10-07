# Existing decisions have no historical snapshot. Never present a reconstruction
# as the reason that actually triggered a previous decision.
class ModerationReasonReport
  LABELS = {
    'non_japanese_profile' => 'サークル名・詳細情報にひらがな・カタカナが含まれていません。',
    'foreign_links' => 'タイトル・本文にひらがな・カタカナがなく、外部リンクが2件以上あります。',
    'duplicate_content' => 'サイト全体に同じ本文のブログが2件以上あります（この投稿を除く）。',
    'frequent_posts' => '同じサークルの直近1時間に既存の投稿が3件以上あります（4件目以降の投稿）。'
  }.freeze

  def self.snapshot(codes)
    codes.map { |code| { 'code' => code, 'message' => LABELS.fetch(code) } }
  end

  def self.for_records(records)
    records = records.uniq { |record| [record.class.name, record.id] }
    legacy_blogs = records.select { |record| record.is_a?(Blog) && record.moderation_status != 'clear' && !(record.moderation_reasons.present? && record.moderation_checked_at.present?) }
    # One body-comparison scan per list, rather than one scan per old blog.
    duplicate_counts = Blog.where(content: legacy_blogs.map(&:content).compact.uniq).group(:content).count if legacy_blogs.any?
    records.to_h { |record| [[record.class.name, record.id], build(record, duplicate_counts: duplicate_counts)] }
  end

  def self.build(record, duplicate_counts: nil)
    saved = record.moderation_reasons.present? && record.moderation_checked_at.present?
    messages = if saved
      record.moderation_reasons.filter_map { |reason| reason['message'] if reason.is_a?(Hash) }.map(&:to_s)
    elsif record.moderation_status == 'review'
      codes = if record.is_a?(Blog)
        count = duplicate_counts ? [duplicate_counts.fetch(record.content, 0) - 1, 0].max : nil
        record.moderation_rule_reasons(at: record.created_at || Time.current, check_recent: true, duplicate_count: count)
      else
        record.moderation_rule_reasons
      end
      snapshot(codes).map { |reason| reason.fetch('message') }
    else
      []
    end
    notes = []
    if record.moderation_status == 'blocked'
      notes << '運営による公開停止中です。具体的な停止理由は記録されていません。'
    elsif record.moderation_status == 'review' && !saved
      notes << '当時の判定理由は未保存です。以下は現在の本文・投稿履歴から確認できる参考情報です。'
      notes << '現在のデータでは該当条件を確認できません。内容修正・投稿削除などで、判定時の状況と異なる可能性があります。' if messages.empty?
    end
    if record.is_a?(User)
      if record.moderation_status == 'clear' && record.moderation_rule_reasons.any?
        notes << '現在の公開条件：サークル名・詳細情報にひらがな・カタカナが含まれていません。'
      end
      notes << "公開に不足する項目：#{record.missing_publication_fields.join('、')}" if record.publication_status == 'draft' && record.missing_publication_fields.any?
      notes << 'サークルが非公開対象（NG）に設定されています。' if record[:ng_account] == 'NG'
      notes << '主催者アカウントが非公開対象に設定されています。' if record.admin_user && !record.admin_user.publicly_visible?
    end
    { messages: messages, notes: notes, checked_at: saved ? record.moderation_checked_at : nil, saved: saved }
  end
end
