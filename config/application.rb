require_relative 'boot'

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Circle
  class Application < Rails::Application
    # Preserve existing cookies, serialization and database behavior during
    # the runtime migration. Adopt newer Rails defaults in separate, tested
    # changes so the old and new servers can coexist during rollback.
    config.load_defaults 6.0
    config.time_zone = 'Tokyo'

    config.i18n.default_locale = :ja
    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.

    # Rack::Attack is installed by its Railtie; rules live in rack_attack.rb.
  end
end
