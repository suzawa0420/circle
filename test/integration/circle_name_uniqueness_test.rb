require 'test_helper'
require_relative '../support/chat_records'

class CircleNameUniquenessTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup { create_chat_records }

  def login
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
  end

  test 'same owner cannot create the same name including surrounding Japanese whitespace' do
    [@circle.name, " \t#{@circle.name}\n　"].each do |name|
      duplicate = @circle.dup
      duplicate.name = name
      assert_not duplicate.save
      assert_match '同じアカウントですでに登録', duplicate.errors[:name].join
      assert_equal name, duplicate.name
    end
    duplicate = @circle.dup
    assert_not duplicate.save(validate: false)
    assert_match '同じアカウントですでに登録', duplicate.errors[:name].join
  end

  test 'other owners can use the same name and existing spelling is preserved' do
    other_owner = AdminUser.create!(email: 'same-name-owner@example.test', password: 'test-password-123')
    circle = @circle.dup
    circle.admin_user = other_owner
    assert circle.save
    original = "　別の サークル　"
    circle.update!(name: original)
    assert_equal original, circle.reload.name
    assert circle.update(name: '別のサークル')
    assert @circle.update(name: @circle.name)
  end

  test 'owner transfer and rename reject duplicates excluding the record itself' do
    second = @circle.dup
    second.name = '別の登録済みサークル'
    second.save!
    assert_not second.update(name: "　#{@circle.name} ")
    assert_equal '別の登録済みサークル', second.reload.name
    second.update!(admin_user: AdminUser.create!(email: 'name-transfer@example.test', password: 'test-password-123'), name: @circle.name)
    assert_not second.update(admin_user: @owner)
    assert_match '同じアカウントですでに登録', second.errors[:name].join
  end

  test 'legacy duplicates remain editable unless their name or account changes' do
    legacy = @circle.dup
    legacy.name = '旧データ検証用の仮名'
    legacy.save!
    legacy.update_columns(name: "　#{@circle.name} ")
    assert legacy.reload.update(area: '更新した活動場所')
    assert_equal "　#{@circle.name} ", legacy.reload.name
    assert @circle.update(schedule: '毎週日曜')
    assert_not @circle.dup.save
    assert legacy.update(name: '重複を解消したサークル名')
  end

  test 'failed create retains all form input and returns a Japanese duplicate error' do
    login
    assert_no_difference 'User.count' do
      post users_path, params: { user: { name: @circle.name, category_id: @circle.category_id,
        event_id: @circle.event_id, prefecture_id: @circle.prefecture_id, area: '保持する場所', schedule: '日曜日' } }
    end
    assert_response :unprocessable_entity
    assert_select '.form-error_message', text: /同じアカウントですでに登録/
    assert_select "input[name='user[name]'][value='#{@circle.name}']"
    assert_select "input[name='user[area]'][value='保持する場所']"
    assert_select "input[name='user[schedule]'][value='日曜日']"
    assert_select '#circle-name-help'
  end

  test 'failed rename retains input and a subsequent distinct name can be saved' do
    second = @circle.dup
    second.name = 'もう一つのサークル'
    second.save!
    login
    patch user_path(second), params: { user: { name: @circle.name, area: '保持する編集内容' } }
    assert_response :unprocessable_entity
    assert_select '.form-error_message', text: /同じアカウントですでに登録/
    assert_select "input[name='user[area]'][value='保持する編集内容']"
    assert_equal 'もう一つのサークル', second.reload.name
    patch user_path(second), params: { user: { name: '新しいサークル名' } }
    assert_redirected_to "/users/#{second.id}/edit2"
    assert_equal '新しいサークル名', second.reload.name
  end

  test 'submitting the same registration again does not create another circle' do
    login
    payload = { user: { name: '繰り返し送信するサークル', category_id: @circle.category_id,
      event_id: @circle.event_id, prefecture_id: @circle.prefecture_id } }
    assert_difference 'User.count', 1 do
      post users_path, params: payload
      assert_response :redirect
      post users_path, params: payload
      assert_response :unprocessable_entity
    end
    assert_select '.form-error_message', text: /同じアカウントですでに登録/
  end
end
