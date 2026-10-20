require 'cgi'

class ReviewDeliveryServiceProfiles < ActiveRecord::Migration[8.1]
  # Keep the rollout independent of future policy changes and model callbacks.
  FIELDS = %w[name appeal goal area schedule requirement cost member recruitment
              contact web line_id twitter instagram item foundation age].freeze
  DETAIL_FIELDS = %w[activity_style experience trial equipment meeting_area destination trip_type].freeze
  PHRASE = /(?:高品質な?|高級な?|厳選された)デリバリーサービス/
  MESSAGE = '「高品質なデリバリーサービス」などの表現が含まれています。性的サービスの宣伝の可能性があるため確認が必要です。'

  class Profile < ActiveRecord::Base
    self.table_name = 'users'
  end

  def up
    columns = FIELDS.map { |field| connection.quote_column_name(field) }
    Profile.where(moderation_status: 'clear')
      .where("concat_ws(' ', #{columns.join(', ')}, sport_details::text) ~ '高|厳|&#'")
      .find_each do |profile|
        profile.with_lock do
          next unless profile.moderation_status == 'clear'
          values = FIELDS.map { |field| profile[field] } +
            DETAIL_FIELDS.map { |field| (profile.sport_details || {})[field] }
          next unless values.any? { |value| matches?(value) }

          profile.update_columns(moderation_status: 'review',
            moderation_reasons: [{ 'code' => 'adult_service_promotion', 'message' => MESSAGE }],
            moderation_checked_at: Time.current)
        end
      end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Later human moderation decisions must be preserved'
  end

  private

  def matches?(value)
    ActionView::Base.full_sanitizer.sanitize(CGI.unescapeHTML(value.to_s))
      .unicode_normalize(:nfkc).downcase.gsub(/[[:space:]\p{Cf}\p{P}\p{S}]/, '').match?(PHRASE)
  end
end
