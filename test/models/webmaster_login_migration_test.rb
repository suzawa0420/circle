require 'test_helper'
require_relative '../../db/migrate/20261002010000_transfer_legacy_webmaster_login'

class WebmasterLoginMigrationTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  test 'only legacy owner one is copied and both logins remain usable' do
    owner = AdminUser.create!(id: 1, email: 'legacy-master@example.test', password: 'migration-test-password')
    AdminUser.create!(id: 2, email: 'ordinary-owner@example.test', password: 'other-test-password')
    assert_difference('Webmaster.count', 1) { TransferLegacyWebmasterLogin.new.up }
    master = Webmaster.find(1)
    assert_equal owner.email, master.email
    assert master.valid_password?('migration-test-password')
    assert owner.reload.valid_password?('migration-test-password')
    assert_equal 1, Webmaster.count
    assert_not owner.master_account?
  end

  test 'existing webmaster is never overwritten on retry' do
    master = Webmaster.create!(id: 1, email: 'existing@example.test', password: 'existing-test-password')
    AdminUser.create!(id: 1, email: 'old@example.test', password: 'migration-test-password')
    assert_no_difference('Webmaster.count') { TransferLegacyWebmasterLogin.new.up }
    assert_equal 'existing@example.test', master.reload.email
    assert master.valid_password?('existing-test-password')
  end

  test 'missing source stops migration rather than granting another owner access' do
    AdminUser.create!(id: 2, email: 'other@example.test', password: 'other-test-password')
    assert_raises(RuntimeError) { TransferLegacyWebmasterLogin.new.up }
    assert_equal 0, Webmaster.count
  end
end
