require 'test_helper'
require_relative '../support/chat_records'

class CircleLevelRankingTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords
  setup { create_chat_records }

  def clone_circle(points, time)
    User.create!(@circle.attributes.except('id', 'created_at', 'updated_at', 'unique_id').merge(cb_point: points, last_post: time.to_s))
  end

  test 'integer levels and maximum use activity time rather than fractional or surplus points' do
    older_max = clone_circle(1000, 3.days.ago)
    newer_max = clone_circle(100, 1.day.ago)
    older = clone_circle(64.9, 3.days.ago)
    newer = clone_circle(64.1, 1.day.ago)
    lower = clone_circle(63.9, Time.current)
    ids = [older_max, newer_max, older, newer, lower].map(&:id)
    expected = [newer_max, older_max, newer, older, lower].map(&:id)
    assert_equal expected, User.where(id: ids).sort_2.pluck(:id)
    assert_equal expected, User.where(id: ids).user_sort_2.pluck(:id)
  end

  test 'popular ordering has a matching database index' do
    connection = ActiveRecord::Base.connection
    connection.execute('SET LOCAL enable_seqscan = off')
    # This checks index/order compatibility, not the planner's cost choice for
    # a handful of fixtures, where sorting a different index can be cheaper.
    connection.execute('SET LOCAL enable_sort = off')
    connection.execute('SET LOCAL enable_incremental_sort = off')
    plan = connection.select_values('EXPLAIN ' + User.sort_2.limit(20).select(:id).to_sql).join("\n")
    assert_includes plan, 'index_users_on_circle_level_order'
  end

  test 'new blog advances activity but edit delete and identical repost do not' do
    login_owner
    content = 'みんなで楽しくバスケットボールの練習をしました。' * 8
    travel_to(Time.zone.local(2026, 10, 2, 10)) do
      token = blog_token(new_circle_blog_path(@circle))
      post circle_blogs_path(@circle), params: { blog: { title: '練習報告', content: content }, spam_form_token: token, contact_website: '' }
      assert_response :redirect
      assert_in_delta 0.2, @circle.reload.cb_point
      stamp = @circle.last_post
      blog = @circle.blogs.last
      travel 1.hour
      token = blog_token(edit_circle_blog_path(@circle, blog))
      patch circle_blog_path(@circle, blog), params: { blog: { title: '練習報告を修正' }, spam_form_token: token, contact_website: '' }
      assert_response :redirect
      assert_equal stamp, @circle.reload.last_post
      delete circle_blog_path(@circle, blog)
      assert_response :redirect
      assert_equal 0, @circle.reload.cb_point
      assert_equal stamp, @circle.last_post
      token = blog_token(new_circle_blog_path(@circle))
      post circle_blogs_path(@circle), params: { blog: { title: '再投稿', content: content }, spam_form_token: token, contact_website: '' }
      assert_response :redirect
      assert_equal stamp, @circle.reload.last_post
      assert_in_delta 0.2, @circle.cb_point
    end
  end

  test 'only first nonempty answer advances activity even after clearing answer or changing question' do
    login_owner
    question = @circle.questions.create!(content: '初参加でも大丈夫ですか？')
    travel_to(Time.zone.local(2026, 10, 2, 10)) do
      patch user_question_path(@circle, question), params: { question: { answer: '大丈夫です。' } }
      assert_response :redirect
      stamp = @circle.reload.last_post
      assert_in_delta 0.3, @circle.cb_point
      travel 1.hour
      patch user_question_path(@circle, question), params: { question: { answer: '初心者も歓迎です。' } }
      assert_equal stamp, @circle.reload.last_post
      patch user_question_path(@circle, question), params: { question: { answer: '' } }
      assert_equal 0, @circle.reload.cb_point
      patch user_question_path(@circle, question), params: { question: { content: '一人でも参加できますか？', answer: '歓迎します。' } }
      assert_equal stamp, @circle.reload.last_post
    end
  end

  test 'owner can publish an initial question and answer as a single activity' do
    login_owner
    post user_questions_path(@circle), params: { question: { content: '一人でも参加できますか？', answer: '歓迎します。' } }
    assert_response :redirect
    assert @circle.reload.last_post.present?
    assert_in_delta 0.3, @circle.cb_point
  end

  test 'new schedule advances activity and repost of deleted legacy schedule does not' do
    login_owner
    data = { title: '週末の練習', venue: '体育館', day: 7.days.from_now.to_date.to_s }
    post user_schedules_path(@circle), params: { schedule: data }
    assert_response :redirect
    stamp = @circle.reload.last_post
    assert_in_delta 0.1, @circle.cb_point
    schedule = @circle.schedules.last
    delete user_schedule_path(@circle, schedule)
    assert_equal 0, @circle.reload.cb_point
    post user_schedules_path(@circle), params: { schedule: data }
    assert_equal stamp, @circle.reload.last_post
  end

  test 'deleting a pre-migration blog keeps a fingerprint and blocked posts do not advance activity' do
    blog = @circle.blogs.create!(title: '過去の活動', content: '仲間と楽しく活動しています。' * 10)
    content = blog.content
    blog.destroy!
    repost = @circle.blogs.create!(title: '再投稿', content: content)
    refute CircleActivityRecorder.record(repost)
    repost.update_columns(moderation_status: 'blocked')
    refute CircleActivityRecorder.record(repost)
  end

  private

  def blog_token(path)
    get path
    assert_response :success
    Nokogiri::HTML(response.body).at_css('input[name="spam_form_token"]')['value']
  end

  def login_owner
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
  end
end
