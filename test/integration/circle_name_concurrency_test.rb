require 'test_helper'
require_relative '../support/chat_records'

class CircleNameConcurrencyTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  self.use_transactional_tests = false
  include ChatRecords

  setup { create_chat_records }

  teardown do
    if @circle
      event, category, prefecture = @circle.event, @circle.category, @circle.prefecture
      @owner.users.destroy_all
      @owner.destroy!
      @member.destroy!
      @other_member.destroy!
      event.destroy!
      category.destroy!
      prefecture.destroy!
    end
  end

  test 'parallel creates cannot both pass the name check and commit' do
    records = 2.times.map { @circle.dup.tap { |circle| circle.name = '並列登録サークル' } }
    assert_serialized_names(records)
  end

  test 'parallel rename and create use the same account lock' do
    records = [@circle, @circle.dup]
    records.each { |circle| circle.name = '並列変更サークル' }
    assert_serialized_names(records)
  end

  test 'parallel renames cannot commit the same new name' do
    other = @circle.dup
    other.name = '変更前の別サークル'
    other.save!
    records = [@circle, other]
    records.each { |circle| circle.name = '同時に変更するサークル' }
    assert_serialized_names(records)
  end

  private

  def assert_serialized_names(records)
    ready, start = Queue.new, Queue.new
    records.each do |record|
      original_check = record.method(:circle_name_not_used_by_owner)
      calls = 0
      record.define_singleton_method(:circle_name_not_used_by_owner) do
        original_check.call
        calls += 1
        # Both validations must finish before either save can acquire the lock.
        # A normal uniqueness validator without the locked recheck fails here.
        if calls == 1
          ready << true
          start.pop
        end
      end
    end
    threads = records.map do |record|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { record.save }
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    assert_equal [false, true], threads.map(&:value).sort_by { |value| value ? 1 : 0 }
    assert_equal 1, @owner.users.where(name: records.first.name).count
    assert records.any? { |record| record.errors[:name].join.include?('同じアカウントですでに登録') }
  end
end
