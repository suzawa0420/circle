require 'test_helper'
require_relative '../support/chat_records'

class MemberCompositionTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    @age = Age.create!(name: '20代')
    @group = Group.create!(name: '社会人')
    @tag = Tag.create!(name: '初心者歓迎')
    @city = City.create!(name: '世田谷区', city_kana: 'synthetic-setagaya', prefecture: @circle.prefecture)
    @circle.create_link!(unique_id: 'synthetic')
    @circle.update!(age_ids: [@age.id], group_ids: [@group.id], tag_ids: [@tag.id], city_ids: [@city.id])
    @step2 = "/users/#{@circle.id}/edit2"
  end

  def sign_in(admin = @owner)
    post admin_user_session_path, params: { admin_user: { email: admin.email, password: 'test-password-123' } }
  end

  test 'profile form offers six optional five point choices directly after the existing search tags' do
    sign_in
    get edit_user_path(@circle)
    assert_response :success
    assert_select 'input[name="user[member]"]'
    assert_select 'input[name="user[age_ids][]"]', false
    assert_select '[data-member-composition]', false
    assert_select 'input[name="user[group_ids][]"]', false
    get @step2
    assert_response :success
    assert_equal ['現在のメンバー', '募集対象', '検索用タグ'], css_select('section.edit02_warp h2').map(&:text)
    assert_select 'section:has(input[name="user[age_ids][]"]) .cb-composition-editor'
    assert_select 'input[name="user[link_attributes][unique_id]"][value=synthetic]'
    assert_select 'input[name="user[city_ids][]"][checked]'
    assert_select '[data-composition-age]', count: 6
    assert_select '#member-age-teens option[value="0"]', text: '0%'
    assert_select '#member-age-teens option[value="5"]', text: '5%'
    assert_select '#member-age-teens option[value="100"]', text: '100%'
    assert_select '[data-composition-female-field][hidden]'
    assert_select '[data-composition-male] option[value=""]', text: '未入力'
  end

  test 'adding another circle retains the optional fields' do
    sign_in
    get '/user/add'
    assert_response :success
    assert_select '[data-composition-age]', count: 6
    assert_select '[data-composition-male]'
  end

  test 'first-time registration retains the optional fields and saves them' do
    registrant = AdminUser.create!(email: 'new-composition-owner@example.test', password: 'test-password-123', email_verified_at: Time.current)
    sign_in(registrant)
    get new_user_path
    assert_response :success
    assert_select 'input[name="user[age_ids][]"][type=checkbox]'
    assert_select '[data-composition-age]', count: 6
    assert_select '[data-composition-male]'
    assert_select 'input[name="user[group_ids][]"][type=checkbox]'
    post users_path, params: { user: { name: '登録テストサークル', event_id: @circle.event_id,
                                     category_id: @circle.category_id, prefecture_id: @circle.prefecture_id,
                                     area: '世田谷区', schedule: '毎週土曜', appeal: @circle.appeal,
                                     age_ids: [@age.id], group_ids: [@group.id],
                                     member_age_percentages: { twenties: '100' }, member_male_percentage: '45' } }
    created = registrant.users.sole
    assert_redirected_to "/users/#{created.id}/edit2"
    assert_equal 45, created.member_male_percentage
    assert_equal 100, created.member_age_percentages.fetch('twenties')
  end

  test 'only configured blocks are published and edits do not change age search tags' do
    get circle_path(@circle)
    assert_response :success
    assert_select '.cb-composition-display', false
    sign_in
    patch @step2, params: { user: { member_age_percentages: { twenties: '25', thirties: '75' } } }
    assert_response :redirect
    assert_equal [@age.id], @circle.reload.age_ids
    assert_equal [0, 25, 75, 0, 0, 0], HasMemberComposition::BANDS.keys.map { |key| @circle.member_age_percentages.fetch(key) }
    get circle_path(@circle)
    assert_select '.cb-composition-axis span', count: 5
    assert_select '.cb-composition-bar-fill', count: 6
    assert_select '.cb-composition-bars li[aria-label="30代 75%"]'
    assert_select '.cb-composition-bars li:last-child .cb-composition-band', text: '60歳以上'
    assert_select '.cb-composition-gender-bar', false

    patch @step2, params: { user: { member_male_percentage: '0', member_age_percentages: HasMemberComposition::BANDS.keys.index_with { '' } } }
    assert_response :redirect
    assert_nil @circle.reload.member_age_percentages
    assert_equal 0, @circle.member_male_percentage
    get circle_path(@circle)
    assert_select '.cb-composition-bars', false
    assert_select '.cb-composition-gender-labels li', text: /男性.*0%/
    assert_select '.cb-composition-gender-labels li', text: /女性.*100%/
    assert_select '.cb-composition-caption', count: 1, text: '主催者による目安です。'
    assert_not_includes response.body, '男性・女性として把握しているメンバー内の割合です'
    patch @step2, params: { user: { member_male_percentage: '' } }
    assert_response :redirect
    assert_nil @circle.reload.member_male_percentage
    assert_equal [@age.id], @circle.age_ids
  end

  test 'invalid values are rejected, valid entered choices are shown again and unrelated edits preserve values' do
    @circle.update!(member_age_percentages: { 'twenties' => 100 }, member_male_percentage: 65)
    sign_in
    patch @step2, params: { user: { member_age_percentages: { twenties: '25', thirties: '60' }, member_male_percentage: '13', age_ids: [''], group_ids: [''], tag_ids: [''], city_ids: [''] } }
    assert_response :unprocessable_entity
    assert_select '#member-age-twenties option[value="25"][selected]'
    assert_select '#member-age-thirties option[value="60"][selected]'
    assert_includes response.body, '合計を100%'
    assert_includes response.body, '5%刻み'
    assert_select 'input[name="user[tag_ids][]"][value=?]:not([checked])', @tag.id
    assert_equal [@age.id], @circle.reload.age_ids
    assert_equal [@group.id], @circle.group_ids
    assert_equal [@tag.id], @circle.tag_ids
    assert_equal [@city.id], @circle.city_ids
    assert_equal 100, @circle.reload.member_age_percentages.fetch('twenties')
    assert_equal 65, @circle.member_male_percentage
    patch @step2, params: { user: { member_age_percentages: { twenties: '32', thirties: '68' } } }
    assert_response :unprocessable_entity
    patch user_path(@circle), params: { user: { member: '25名程' } }
    assert_response :redirect
    assert_equal 65, @circle.reload.member_male_percentage
    assert_equal 100, @circle.member_age_percentages.fetch('twenties')
  end

  test 'step two saves native associations and derives only submitted search text' do
    sign_in
    patch @step2, params: { user: { age_ids: ['', @age.id], group_ids: ['', @group.id],
                                    tag_ids: ['', @tag.id], city_ids: ['', @city.id],
                                    link_attributes: { id: @circle.link.id, unique_id: 'renamed' } } }
    assert_redirected_to "/users/#{@circle.id}/edit3"
    assert_includes @circle.reload.average_age, '20代'
    assert_includes @circle.grouping, '社会人'
    assert_equal 'renamed', @circle.link.unique_id
    assert_equal [@tag.id], @circle.tag_ids
    patch @step2, params: { user: { age_ids: [''], group_ids: [''] } }
    assert_response :redirect
    assert_empty @circle.reload.age_ids
    assert_empty @circle.group_ids
    assert_not_includes @circle.average_age.to_s, '20代'
    assert_not_includes @circle.grouping.to_s, '社会人'
    assert_equal [@tag.id], @circle.tag_ids
    assert_equal [@city.id], @circle.city_ids
  end

  test 'older step one and two forms keep existing semantics' do
    sign_in
    patch user_path(@circle), params: { user: { age_ids: [''], group_ids: [''], member_male_percentage: '65' } }
    assert_redirected_to @step2
    assert_empty @circle.reload.age_ids
    assert_empty @circle.group_ids
    patch @step2, params: { user: { tag_ids: [''], link_attributes: { id: @circle.link.id, unique_id: 'updated' } } }
    assert_response :redirect
    assert_equal 65, @circle.reload.member_male_percentage
    assert_empty @circle.tag_ids
    assert_equal [@city.id], @circle.city_ids
  end

  test 'another organizer cannot edit or publish percentages' do
    other = AdminUser.create!(email: 'composition-other@example.test', password: 'test-password-123', email_verified_at: Time.current)
    User.create!(@circle.attributes.except('id', 'created_at', 'updated_at', 'unique_id').merge(name: '別のサークル', admin_user: other))
    sign_in(other)
    get @step2
    assert_response :redirect
    patch @step2, params: { user: { member_male_percentage: '40', member_age_percentages: { twenties: '100' } } }
    assert_response :redirect
    assert_nil @circle.reload.member_male_percentage
    assert_nil @circle.member_age_percentages
  end
end
