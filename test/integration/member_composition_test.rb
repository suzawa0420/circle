require 'test_helper'
require_relative '../support/chat_records'

class MemberCompositionTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    @age = Age.create!(name: '20代')
    @circle.update!(age_ids: [@age.id])
  end

  def sign_in(admin = @owner)
    post admin_user_session_path, params: { admin_user: { email: admin.email, password: 'test-password-123' } }
  end

  test 'profile form offers six optional five point choices directly after the existing search tags' do
    sign_in
    get edit_user_path(@circle)
    assert_response :success
    assert_select '.edit01_warp:has(input[name="user[age_ids][]"]) + .cb-composition-editor + .edit01_warp'
    assert_select '[data-composition-age]', count: 6
    assert_select '#member-age-teens option[value="0"]', text: '0%'
    assert_select '#member-age-teens option[value="5"]', text: '5%'
    assert_select '#member-age-teens option[value="100"]', text: '100%'
    assert_select '[data-composition-female-field][hidden]'
    assert_select '[data-composition-male] option[value=""]', text: '未入力'
  end

  test 'only configured blocks are published and edits do not change age search tags' do
    get circle_path(@circle)
    assert_response :success
    assert_select '.cb-composition-display', false
    sign_in
    patch user_path(@circle), params: { user: { member_age_percentages: { twenties: '25', thirties: '75' } } }
    assert_response :redirect
    assert_equal [@age.id], @circle.reload.age_ids
    assert_equal [0, 25, 75, 0, 0, 0], HasMemberComposition::BANDS.keys.map { |key| @circle.member_age_percentages.fetch(key) }
    get circle_path(@circle)
    assert_select '.cb-composition-axis span', count: 5
    assert_select '.cb-composition-bar-fill', count: 6
    assert_select '.cb-composition-bars li[aria-label="30代 75%"]'
    assert_select '.cb-composition-gender-bar', false

    patch user_path(@circle), params: { user: { member_male_percentage: '0', member_age_percentages: HasMemberComposition::BANDS.keys.index_with { '' } } }
    assert_response :redirect
    assert_nil @circle.reload.member_age_percentages
    assert_equal 0, @circle.member_male_percentage
    get circle_path(@circle)
    assert_select '.cb-composition-bars', false
    assert_select '.cb-composition-gender-labels li', text: /男性.*0%/
    assert_select '.cb-composition-gender-labels li', text: /女性.*100%/
    patch user_path(@circle), params: { user: { member_male_percentage: '' } }
    assert_response :redirect
    assert_nil @circle.reload.member_male_percentage
    assert_equal [@age.id], @circle.age_ids
  end

  test 'invalid values are rejected, valid entered choices are shown again and unrelated edits preserve values' do
    @circle.update!(member_age_percentages: { 'twenties' => 100 }, member_male_percentage: 65)
    sign_in
    patch user_path(@circle), params: { user: { member_age_percentages: { twenties: '25', thirties: '60' }, member_male_percentage: '13' } }
    assert_response :unprocessable_entity
    assert_select '#member-age-twenties option[value="25"][selected]'
    assert_select '#member-age-thirties option[value="60"][selected]'
    assert_includes response.body, '合計を100%'
    assert_includes response.body, '5%刻み'
    assert_equal 100, @circle.reload.member_age_percentages.fetch('twenties')
    assert_equal 65, @circle.member_male_percentage
    patch user_path(@circle), params: { user: { member_age_percentages: { twenties: '32', thirties: '68' } } }
    assert_response :unprocessable_entity
    patch user_path(@circle), params: { user: { member: '25名程' } }
    assert_response :redirect
    assert_equal 65, @circle.reload.member_male_percentage
    assert_equal 100, @circle.member_age_percentages.fetch('twenties')
  end

  test 'another organizer cannot edit or publish percentages' do
    other = AdminUser.create!(email: 'composition-other@example.test', password: 'test-password-123', email_verified_at: Time.current)
    User.create!(@circle.attributes.except('id', 'created_at', 'updated_at', 'unique_id').merge(name: '別のサークル', admin_user: other))
    sign_in(other)
    get edit_user_path(@circle)
    assert_response :redirect
    patch user_path(@circle), params: { user: { member_male_percentage: '40', member_age_percentages: { twenties: '100' } } }
    assert_response :redirect
    assert_nil @circle.reload.member_male_percentage
    assert_nil @circle.member_age_percentages
  end
end
