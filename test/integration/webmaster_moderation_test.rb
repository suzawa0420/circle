require 'test_helper'
require_relative '../support/chat_records'

class WebmasterModerationTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords
  setup do
    create_chat_records
    @master = Webmaster.create!(id: 1, email: 'webmaster@example.test', password: 'test-password-123')
  end

  test 'master can delete anonymous legacy review and recalculate score' do
    review = @circle.reviews.create!(review: 0, comment: '匿名の古い口コミです。')
    @circle.reviews.create!(review: 1, comment: '楽しく活動できました。')
    login_master
    get user_reviews_path(@circle)
    assert_select "a[href='#{user_review_path(@circle, review)}'][data-method='delete']"
    delete user_review_path(@circle, review)
    assert_not Review.exists?(review.id)
    assert_equal 5, @circle.reload.review_score.to_f
  end

  test 'legacy member review deletion keeps the original member entitlement not the signed in member' do
    review = @circle.reviews.create!(member: @other_member, review: 1, comment: '参加した時の口コミです。')
    post member_session_path, params: { member: { email: @member.email, password: 'test-password-123' } }
    login_master
    delete user_review_path(@circle, review)
    assert_not Review.exists?(review.id)
    assert Conversation.find_by!(user: @circle, member: @other_member).legacy_member_review?
    assert_not @conversation.reload.legacy_member_review?
  end

  test 'deleting a published circle review preserves peer evaluation and prevents repost' do
    accept_conversation
    @conversation.submit_review!('member', member_evaluation)
    @conversation.submit_review!('owner', owner_evaluation)
    review = @conversation.conversation_reviews.find_by!(author_role: 'member')
    login_master
    delete user_review_path(@circle, review.review)
    assert review.reload.deleted_at
    assert_nil review.reload.review
    assert_nil @conversation.conversation_reviews.find_by!(author_role: 'owner').deleted_at
    assert_raises(Conversation::NotAllowed) { @conversation.submit_review!('member', member_evaluation) }
  end

  test 'master can delete participant evaluation while preserving circle review and private drafts' do
    accept_conversation
    draft = @conversation.submit_review!('owner', owner_evaluation)
    login_master
    get super_admin_reviews_path
    assert_not_includes response.body, draft.comment
    assert_raises(ActiveRecord::RecordNotFound) { delete super_admin_evaluation_path(draft) }
    @conversation.submit_review!('member', member_evaluation)
    get member_profile_path(@member)
    assert_select "form[action='#{super_admin_evaluation_path(draft)}']"
    delete super_admin_evaluation_path(draft)
    assert draft.reload.deleted_at
    assert_equal 0, @member.received_conversation_reviews.count
    assert @conversation.conversation_reviews.find_by!(author_role: 'member').review
  end

  test 'organizer and other participant cannot delete chat reviews' do
    accept_conversation
    @conversation.submit_review!('member', member_evaluation)
    @conversation.submit_review!('owner', owner_evaluation)
    review = @conversation.conversation_reviews.find_by!(author_role: 'member').review
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    assert_no_difference('Review.count') { delete user_review_path(@circle, review) }
    assert_response :forbidden
    delete destroy_admin_user_session_path
    post member_session_path, params: { member: { email: @other_member.email, password: 'test-password-123' } }
    assert_no_difference('Review.count') { delete user_review_path(@circle, review) }
    assert_response :forbidden
    get super_admin_reviews_path
    assert_redirected_to new_webmaster_session_path
  end

  test 'public pages keep the mobile destinations and management header links are distinct' do
    login_master
    [root_path, blogs_path, matches_path, "/places", webmaster_path].each do |path|
      get path
      assert_response :success, path
      [circles_path, login_path].each do |destination|
        assert_select "nav.mobile-bottom-nav a[href='#{destination}']", count: 1
      end
      assert_select 'nav.mobile-bottom-nav > a', count: 2
      assert_select 'nav.mobile-bottom-nav > button', text: 'メニュー', count: 1
      [circles_path, blogs_path, matches_path, "/places"].each do |destination|
        assert_select "#mobile-menu-dialog a[href='#{destination}']", count: 1
      end
    end
    get webmaster_path
    links = css_select('.webmaster-card').map { |a| a['href'] }
    assert_equal links.uniq, links
    assert_includes links, super_admin_reviews_path
    assert_select '.webmaster-nav a[href="/"]', count: 1
    assert_select '.webmaster-nav a[href="/webmaster"]', count: 1
    links.each do |path|
      get path
      assert_response :success, path
    end
  end

  test 'columns are writable only by webmaster including direct create and destroy' do
    assert_no_difference('Column.count') { post columns_path, params: { column: { title: 'テストコラム', text: '本文' } } }
    assert_redirected_to new_webmaster_session_path
    login_master
    assert_difference('Column.count') { post columns_path, params: { column: { title: 'テストコラム', text: '本文' } } }
    column = Column.last
    get column_path(column)
    assert_response :success
    assert_select "a[href='#{edit_column_path(column)}']"
    delete column_path(column)
    assert_not Column.exists?(column.id)
  end

  test 'master can edit circle links and matches while unrelated accounts cannot update them' do
    link = Link.create!(user: @circle, unique_id: 'reviewaudit', link01_title: '元のリンク')
    match = Match.create!(id: @circle.id, user: @circle, recruit: '募集中', comment: '元の募集')
    post member_session_path, params: { member: { email: @member.email, password: 'test-password-123' } }
    patch link_path(link), params: { link: { link01_title: '変更拒否' } }
    assert_equal '元のリンク', link.reload.link01_title
    patch match_path(match), params: { match: { comment: '変更拒否' } }
    assert_equal '元の募集', match.reload.comment
    login_master
    get edit_link_path(link)
    assert_response :success
    patch link_path(link), params: { link: { link01_title: '運営変更' } }
    assert_equal '運営変更', link.reload.link01_title
    get edit_match_path(match)
    assert_response :success
    patch match_path(match), params: { match: { comment: '運営変更' } }
    assert_equal '運営変更', match.reload.comment
  end

  test 'master can remove facility reviews and wrong parent cannot delete them' do
    place = Place.new(name: '運営確認用施設')
    place.save!(validate: false)
    review = place.place_reviews.create!(facility: 1, reservation: 1, price: 1, access: 1, comment: '施設への口コミです。')
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    assert_no_difference('PlaceReview.count') { delete place_place_review_path(place, review) }
    assert_response :forbidden
    login_master
    get super_admin_reviews_path
    assert_select "form[action='#{place_place_review_path(place, review)}']"
    delete place_place_review_path(place, review)
    assert_not PlaceReview.exists?(review.id)
    assert_nil place.reload.average_score
  end

  private
  def login_master
    post webmaster_session_path, params: { webmaster: { email: @master.email, password: 'test-password-123' } }
  end
end
