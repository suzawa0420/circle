module ModerationReasonsHelper
  def moderation_reason_report(record)
    @moderation_reason_reports&.fetch([record.class.name, record.id], nil) || ModerationReasonReport.build(record)
  end
end
