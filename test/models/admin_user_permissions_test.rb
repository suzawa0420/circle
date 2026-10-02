require 'test_helper'

class AdminUserPermissionsTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  test 'organizer id one and legacy moderator flags never grant webmaster privileges' do
    [AdminUser.new(id: 1, email: 'circlebook26@gmail.com', moderator: true),
     AdminUser.new(id: 2, email: 'CircleBook26@Gmail.com', moderator: true)].each do |account|
      assert_not account.master_account?
      assert_not account.super_admin?
      assert_not account.moderator?
    end
  end
end
