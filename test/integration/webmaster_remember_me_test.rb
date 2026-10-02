require 'test_helper'

class WebmasterRememberMeTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  setup do
    @master = Webmaster.create!(id: 1, email: 'remember-master@example.test', password: 'remember-test-password')
  end

  test 'unchecked login expires after thirty minutes and issues no remember cookie' do
    get new_webmaster_session_path
    assert_select 'input[type=checkbox][name="webmaster[remember_me]"]:not([checked])', count: 1
    login('0')
    assert_nil cookies['remember_webmaster_token']
    travel 31.minutes do
      get webmaster_path
      follow_redirect! if response.location == webmaster_url
      assert_redirected_to new_webmaster_session_path
    end
  end

  test 'checked login survives inactivity and a browser session restart' do
    login('1')
    assert cookies['remember_webmaster_token'].present?
    travel 31.minutes do
      get webmaster_path
      assert_response :success
    end
    travel 1.day do
      cookies.delete(Rails.application.config.session_options[:key])
      get webmaster_path
      assert_response :success
    end
  end

  test 'logout revokes the persistent login even if an old cookie is replayed' do
    login('1')
    saved_cookie = cookies['remember_webmaster_token']
    delete destroy_webmaster_session_path
    assert_nil @master.reload.remember_created_at
    cookies.delete(Rails.application.config.session_options[:key])
    cookies['remember_webmaster_token'] = saved_cookie
    get webmaster_path
    assert_redirected_to new_webmaster_session_path
  end

  test 'remembered login expires after two weeks and password changes revoke it' do
    assert_equal 2.weeks, Webmaster.remember_for
    login('1')
    travel 15.days do
      cookies.delete(Rails.application.config.session_options[:key])
      get webmaster_path
      assert_redirected_to new_webmaster_session_path
    end
    login('1')
    @master.update!(password: 'replacement-test-password', password_confirmation: 'replacement-test-password')
    cookies.delete(Rails.application.config.session_options[:key])
    get webmaster_path
    assert_redirected_to new_webmaster_session_path
  end

  private
  def login(remember)
    post webmaster_session_path, params: { webmaster: { email: @master.email, password: 'remember-test-password', remember_me: remember } }
    assert_response :redirect
  end
end
