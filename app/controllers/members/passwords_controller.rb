# frozen_string_literal: true

class Members::PasswordsController < Devise::PasswordsController
  include AccountPasswordRecovery
end
