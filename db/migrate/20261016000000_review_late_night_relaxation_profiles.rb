require 'cgi'

class ReviewLateNightRelaxationProfiles < ActiveRecord::Migration[8.1]
  # Freeze this rollout's rule instead of depending on future model callbacks.
  FIELDS = %w[name appeal goal area schedule requirement cost member recruitment
              contact web line_id twitter instagram item foundation age].freeze
  DETAIL_FIELDS = %w[activity_style experience trial equipment meeting_area destination trip_type].freeze
  MESSAGE = '「深夜舒壓／深夜舒压」の表現が含まれています。性的サービスの宣伝の可能性があるため確認が必要です。'

  class Profile < ActiveRecord::Base
    self.table_name = 'users'
  end

  def up
    # Narrow the scan without excluding HTML, numeric entities or split words.
    columns = FIELDS.map { |field| connection.quote_column_name(field) }
    Profile.where(moderation_status: 'clear')
      .where("concat_ws(' ', #{columns.join(', ')}, sport_details::text) ~ '深|舒|&#'")
      .find_each do |profile|
        profile.with_lock do
          next unless profile.moderation_status == 'clear'
          values = FIELDS.map { |field| profile[field] } +
            DETAIL_FIELDS.map { |field| (profile.sport_details || {})[field] }
          matches = values.any? do |value|
            ActionView::Base.full_sanitizer.sanitize(CGI.unescapeHTML(value.to_s))
              .unicode_normalize(:nfkc).downcase.gsub(/[[:space:]\p{Cf}\p{P}\p{S}]/, '').match?(/深夜舒[壓压]/)
          end
          next unless matches
          profile.update_columns(moderation_status: 'review',
            moderation_reasons: [{ 'code' => 'adult_service_promotion', 'message' => MESSAGE }],
            moderation_checked_at: Time.current)
        end
      end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Later human moderation decisions must be preserved'
  end
end
