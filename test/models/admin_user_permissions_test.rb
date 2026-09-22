require 'test_helper'

class AdminUserPermissionsTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  test "only admin user 1 with the master email is the master account" do
    master = AdminUser.new(id: 1, email: "circlebook26@gmail.com")
    wrong_id = AdminUser.new(id: 2, email: "circlebook26@gmail.com", moderator: true)
    wrong_email = AdminUser.new(id: 1, email: "other@example.com", moderator: true)

    assert master.master_account?
    assert master.super_admin?
    assert master.moderator?
    assert_not wrong_id.master_account?
    assert_not wrong_id.moderator?
    assert_not wrong_email.master_account?
    assert_not wrong_email.moderator?
  end

  test "master email comparison is case insensitive" do
    master = AdminUser.new(id: 1, email: "CircleBook26@Gmail.com")

    assert master.master_account?
  end
end
