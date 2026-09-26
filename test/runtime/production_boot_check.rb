# Standalone production-mode boot with synthetic settings and blocked HTTP.
# No production credentials, data, mail delivery or metadata service is used.
ENV['DATABASE_URL'] = 'postgresql://127.0.0.1:1/circle_runtime_check'
ENV['RAILS_ENV'] = 'production'
ENV['SECRET_KEY_BASE'] = 'runtime-check-only-' + ('0' * 64)
ENV['AWS_EC2_METADATA_DISABLED'] = 'true'
ENV['AWS_ACCESS_KEY_ID'] = 'runtime-check-only'
ENV['AWS_SECRET_ACCESS_KEY'] = 'runtime-check-only'
ENV['AWS_IAM_ACCESS_KEY_ID'] = 'runtime-check-only'
ENV['AWS_IAM_ACCESS_KEY'] = 'runtime-check-only'
ENV['AWS_S3_REGION'] = 'ap-northeast-1'
ENV['AWS_S3_BUCKET'] = 'runtime-check-only'
require 'bundler/setup'
require 'net/http'
require 'tmpdir'

Net::HTTP.prepend(Module.new do
  def request(*)
    raise 'Unexpected network request during production boot check'
  end
end)
require 'aws-sdk-core'
Aws.config[:stub_responses] = true
require 'rails'
require 'dotenv'
require 'dotenv/rails'

Dir.mktmpdir('circle-production-boot-') do |directory|
  # Redirect Dotenv before Application is defined (before_configuration).
  Dotenv::Rails.files = [File.join(directory, 'absent-dotenv')]
  require_relative '../../config/application'
  # Override file paths before initialize!; never decrypt real credentials.
  Rails.application.config.credentials.content_path = File.join(directory, 'absent.enc')
  Rails.application.config.credentials.key_path = File.join(directory, 'absent.key')
  database_config = File.join(directory, 'database.yml')
  File.write(database_config, "production:\n  adapter: postgresql\n  database: circle_runtime_check\n  host: 127.0.0.1\n  port: 1\n")
  Rails.application.config.paths['config/database'] = database_config
  Rails.application.initialize!
  raise 'SES delivery method missing' unless ActionMailer::Base.delivery_methods[:ses] == Aws::ActionMailer::SES::Mailer
  raise 'SES region changed' unless ActionMailer::Base.ses_settings[:region] == 'ap-northeast-1'
  class RuntimeProbeMailer < ActionMailer::Base
    def probe
      mail(from: 'sender@example.test', to: 'recipient@example.test', subject: 'Runtime check', body: 'Synthetic mail; AWS SDK responses are stubbed.')
    end
  end
  RuntimeProbeMailer.probe.deliver_now
  puts "Production-mode boot and stubbed SES delivery passed (Rails #{Rails.version})"
end
