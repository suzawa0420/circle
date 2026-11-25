require 'test_helper'
require_relative '../support/chat_records'

class BlogDuplicateValidationTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    @title = '練習報告'
    @body = '<div>' + 'みんなで楽しくバスケットボールの練習をしました。' * 8 + '</div>'
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
  end

  test 'post rejects matching title and body independently and shows the form errors' do
    @circle.blogs.create!(title: @title, content: @body)
    [[@title, @body + '別の内容です。', true, false],
     ['別のタイトル', @body, false, true],
     [@title, @body, true, true]].each do |title, content, title_duplicate, body_duplicate|
      token = blog_token(new_circle_blog_path(@circle))
      assert_no_difference('Blog.count') do
        post circle_blogs_path(@circle), params: form_params(token, title, content)
      end
      assert_response 422
      assert_select '.form-error_message', text: /同じタイトル/, count: title_duplicate ? 1 : 0
      assert_select '.form-error_message', text: /同じ本文/, count: body_duplicate ? 1 : 0
      assert_select 'input[name="blog[title]"][value=?]', title
      assert_select 'input[name="blog[content]"][value=?]', content
    end
    assert_equal 'clear', @circle.blogs.first.moderation_status
  end

  test 'exact seven day boundary is rejected but older posts and other circles do not block' do
    freeze_time do
      other_circle = User.create!(@circle.attributes.except('id', 'created_at', 'updated_at', 'unique_id').merge(name: '別の練習サークル'))
      other_circle.blogs.create!(title: @title, content: @body)
      original = @circle.blogs.create!(title: @title, content: @body, created_at: 7.days.ago)
      refute @circle.blogs.build(title: @title, content: @body).valid?
      original.update_column(:created_at, 7.days.ago - 1.second)
      token = blog_token(new_circle_blog_path(@circle))
      assert_difference('Blog.count', 1) do
        post circle_blogs_path(@circle), params: form_params(token, @title, @body)
      end
      assert_response :redirect
      assert_equal 'clear', @circle.blogs.reorder(:id).last.moderation_status
    end
  end

  test 'edit checks changed fields only and leaves the persisted blog unchanged on failure' do
    @circle.blogs.create!(title: @title, content: @body)
    blog = @circle.blogs.create!(title: '別の練習', content: @body + '次回も楽しみです。')
    token = blog_token(edit_circle_blog_path(@circle, blog))
    patch circle_blog_path(@circle, blog), params: form_params(token, @title, blog.content)
    assert_response 422
    assert_select '.form-error_message', text: /同じタイトル/
    assert_equal '別の練習', blog.reload.title
    token = blog_token(edit_circle_blog_path(@circle, blog))
    patch circle_blog_path(@circle, blog), params: form_params(token, 'タイトルを修正', blog.content)
    assert_response :redirect
    assert_equal 'タイトルを修正', blog.reload.title
  end

  private

  def blog_token(path)
    get path
    assert_response :success
    Nokogiri::HTML(response.body).at_css('input[name="spam_form_token"]')['value']
  end

  def form_params(token, title, content)
    { blog: { title: title, content: content }, spam_form_token: token, contact_website: '' }
  end
end
