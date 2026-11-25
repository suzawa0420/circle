# frozen_string_literal: true

class AdminUsers::PasswordsController < Devise::PasswordsController
  include AccountPasswordRecovery
end
