require_relative '../test_helper'
require_relative '../support/chat_records'

class PublicListingPreviewTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  include ChatRecords

  setup { create_chat_records }

  test 'preview matches the original order across normal flagged and hidden owners' do
    owners = [@owner, AdminUser.create!(email: 'flagged@example.test', password: 'test-password-123', check: 1),
      AdminUser.create!(email: 'hidden@example.test', password: 'test-password-123', check: 3)]
    owners.each_with_index do |owner, index|
      7.times do |i|
        circle = User.create!(name: "検証サークル#{index}-#{i}", appeal: @circle.appeal, category: @circle.category,
          event: @circle.event, prefecture: @circle.prefecture, admin_user: owner, switch: '募集中', cb_point: i * 10)
        Blog.insert_all!([{ user_id: circle.id, title: '公開記事', content: '長い本文' * 1000,
          image_01: 'sample.jpg', moderation_status: 'clear', created_at: Time.current, updated_at: Time.current + i.hours }])
        Match.create!(user: circle, recruit: '募集中', updated_at: Time.current + i.hours)
      end
    end
    relations = [User.publicly_visible.sort_2,
      Blog.publicly_visible.order(updated_at: :desc, id: :desc).moderation_last,
      Match.where(recruit: '募集中', user_id: User.publicly_visible.select(:id)).order(updated_at: :desc, id: :desc).moderation_last]
    relations.each do |relation|
      [1, 5, 12, 30].each do |limit|
        assert_equal relation.limit(limit).pluck(:id), PublicListingPreview.call(relation, limit: limit).pluck(:id)
      end
      preview = PublicListingPreview.call(relation, limit: 5)
      @owner.update_column(:check, 3)
      assert_empty preview.to_a, 'Visibility must be rechecked after selecting IDs'
      @owner.update_column(:check, nil)
    end
  end

  test 'empty previews remain empty and reject incompatible relations' do
    assert_empty PublicListingPreview.call(User.none.sort_2, limit: 5)
    assert_raises(ArgumentError) { PublicListingPreview.call(User.publicly_visible, limit: 5) }
    assert_raises(ArgumentError) { PublicListingPreview.call(User.publicly_visible.sort_2.limit(2), limit: 5) }
  end
end
