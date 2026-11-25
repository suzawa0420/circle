# frozen_string_literal: true

require 'test_helper'
require_relative '../support/chat_records'

class CircleImageSaveProcessingTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  module ProcessingProbe
    def normalize_image
      Thread.current[:circle_image_processing_probe]&.push(mounted_as)
      super
    end
  end
  ImageUploader.prepend(ProcessingProbe)

  setup do
    create_chat_records
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    assert_response :redirect
    Thread.current[:circle_image_processing_probe] = []
  end

  teardown { Thread.current[:circle_image_processing_probe] = nil }

  test 'processing runs once for a new cover and does not reprocess stored uploads when editing text' do
    uploaded = Rack::Test::UploadedFile.new(Rails.root.join('public/images/listing-default-header-v1.jpg'), 'image/jpeg')
    patch user_path(@circle), params: { user: { pic_header: uploaded } }
    assert_response :redirect
    assert_equal [:pic_header], Thread.current[:circle_image_processing_probe]
    cover_id = @circle.reload[:pic_header]
    assert cover_id.present?
    assert_equal 1, @circle.event.reload.users_count

    Thread.current[:circle_image_processing_probe].clear
    patch user_path(@circle), params: { user: { area: '新しい活動エリア' } }
    assert_response :redirect
    assert_empty Thread.current[:circle_image_processing_probe]
    assert_equal cover_id, @circle.reload[:pic_header]
    assert_equal 1, @circle.event.reload.users_count
  end

  test 'the existing sport counter is maintained on creation, sport change and deletion' do
    previous = @circle.event
    next_event = Event.create!(name: 'テスト種目', ruby: 'new-test-sport', category: previous.category, order: '3')
    assert_equal 1, previous.reload.users_count
    assert_equal 0, next_event.reload.users_count
    @circle.update!(event: next_event)
    assert_equal 0, previous.reload.users_count
    assert_equal 1, next_event.reload.users_count
    @circle.destroy!
    assert_equal 0, next_event.reload.users_count
  end
end
