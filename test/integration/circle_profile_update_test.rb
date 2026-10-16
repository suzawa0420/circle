require 'test_helper'
require_relative '../support/chat_records'

class CircleProfileUpdateTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    @master = Webmaster.create!(id: 1, email: 'webmaster@example.test', password: 'test-password-123')
  end

  test 'webmaster can reclassify a legacy circle with AV inside an English word' do
    @circle.update_columns(name: 'HEARTWAVE99(ピックルボールサークル)')
    sport = Event.create!(name: 'ピックルボール', ruby: 'test-pickleball', category: @circle.category)
    login_master
    patch user_path(@circle), params: { user: { event_id: sport.id } }
    assert_redirected_to "/users/#{@circle.id}/edit2"
    assert_equal sport.id, @circle.reload.event_id
    assert_equal 'HEARTWAVE99(ピックルボールサークル)', @circle.name
  end

  test 'invalid webmaster update renders validation errors and the correct owner form' do
    login_master
    original_name = @circle.name
    patch user_path(@circle), params: { user: { name: '' } }
    assert_response :unprocessable_entity
    assert_select '.form-error_message'
    assert_select "form[action='/users/#{@circle.id}/admin_user_update']"
    assert_equal original_name, @circle.reload.name
  end

  test 'invalid owner update renders errors without administrative controls' do
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    patch user_path(@circle), params: { user: { event_id: '' } }
    assert_response :unprocessable_entity
    assert_select '.form-error_message'
    assert_select "form[action='/users/#{@circle.id}/admin_user_update']", count: 0
    assert @circle.reload.event_id.present?
  end

  test 'webmaster validation uses the target owner even with a different owner session' do
    other = AdminUser.create!(email: 'different-owner@example.test', password: 'test-password-123')
    post admin_user_session_path, params: { admin_user: { email: other.email, password: 'test-password-123' } }
    @owner.update!(check: 1)
    login_master
    patch user_path(@circle), params: { user: { name: '' } }
    assert_response :unprocessable_entity
    assert_select 'select[name="admin_user[check]"] option[selected][value="1"]'
  end

  test 'webmaster can see errors for a legacy circle without an owner' do
    @circle.update_columns(admin_user_id: nil)
    login_master
    patch user_path(@circle), params: { user: { name: '' } }
    assert_response :unprocessable_entity
    assert_select '.form-error_message'
    assert_select "form[action='/users/#{@circle.id}/admin_user_update']", count: 0
  end

  test 'remaining prohibited terms are rejected while AV is accepted' do
    %w[風俗 escort ESCORT].each do |name|
      @circle.name = name
      refute @circle.valid?, name
      assert @circle.errors.of_kind?(:name, :invalid), name
    end
    %w[AV av AV鑑賞 鑑賞AV AV99 HEARTWAVE99 WAVE BRAVE travel].each do |name|
      @circle.name = name
      assert @circle.valid?, name
    end
    @circle.name = '通常のサークル'
    %i[appeal goal].each do |field|
      @circle[field] = 'AV鑑賞'
      assert @circle.valid?
    end
  end

  test 'owner can save reply templates containing http and https URLs' do
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    template = "集合場所はこちらです。http://example.test/map\n詳細：https://example.test/info"
    patch inquiry_settings_path(@circle), params: { user: { template: template } }
    assert_redirected_to inquiry_settings_path(@circle)
    assert_equal template, @circle.reload.template
  end

  test 'all edit steps link to each other with the current step marked' do
    login_master
    paths = [edit_user_path(@circle), "/users/#{@circle.id}/edit2", "/users/#{@circle.id}/edit3"]
    paths.each do |path|
      get path
      assert_response :success
      paths.each { |destination| assert_select ".step_bar a[href='#{destination}']", count: 1 }
      assert_select ".step_bar a[aria-current='step'][href='#{path}']", count: 1
    end
  end

  test 'main and sub prefectures have separate select all controls and retain saved cities' do
    sub = Prefecture.create!(name: '神奈川県', kana: 'edit-kanagawa', order: '2', sort: 2)
    main_city = City.create!(name: '千代田区', prefecture: @circle.prefecture)
    sub_city = City.create!(name: '横浜市', prefecture: sub)
    @circle.update!(prefecture_sub_id: sub.id, city_ids: [main_city.id])
    login_master
    get "/users/#{@circle.id}/edit2"
    assert_response :success
    assert_select '[data-city-selection]', count: 2
    assert_select '#main-cities-all[data-city-select-all]'
    assert_select '#sub-cities-all[data-city-select-all]'
    assert_select "#main-cities input[value='#{main_city.id}'][checked]"
    assert_select "#sub-cities input[value='#{sub_city.id}']:not([checked])"
    assert_select 'input[name="user[city_ids][]"][type=checkbox]', count: 2
  end

  private

  def login_master
    post webmaster_session_path, params: { webmaster: { email: @master.email, password: 'test-password-123' } }
  end
end
