source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '2.7.6'

gem 'rails', '~> 6.0.5.1'
gem 'puma', '~> 3.11'
gem 'sass-rails', '~> 5.0'
gem 'sassc-rails'
gem 'terser'

gem 'execjs'


gem 'coffee-rails', '~> 4.2'
gem 'turbolinks', '~> 5'
gem 'jbuilder', '~> 2.5'
gem 'mini_magick', '~> 4.8'

gem 'gretel'
gem 'zeroclipboard-rails'

gem 'bootsnap', '>= 1.1.0', require: false

gem 'tzinfo-data', platforms: [:mingw, :mswin, :x64_mingw, :jruby]

gem 'seed-fu'
gem 'paperclip'

gem 'rails-i18n'

gem 'devise'
gem 'devise-i18n'
gem 'devise-i18n-views'

gem 'kaminari'
gem 'jquery-rails'

gem 'bootstrap-sass', '~> 3.3.7'
gem "font-awesome-rails"
gem 'momentjs-rails'
gem "rack-cors"

# for security
gem 'rack-attack'

gem 'carrierwave'

gem 'cloudinary'
gem 'dotenv-rails'

gem 'fog-aws'

gem 'meta-tags'
gem 'sitemap_generator'

gem 'aws-sdk'
gem "aws-sdk-s3", require: false
gem 'aws-sdk-rails'

gem 'whenever', :require => false
gem 'rack-rewrite'

gem 'rinku'
gem 'rails_autolink'
gem 'ransack'

gem 'counter_culture'
gem 'cocoon'
gem 'trix'

gem 'hirb'         # 出力結果を表として出力するgem
gem 'hirb-unicode'  # マルチバイト文字の表示を補正するgem
gem 'uri', '0.10.0'

gem 'haml-rails'
gem 'erb2haml'

gem 'active_decorator'
gem 'active_model_serializers'

gem 'annotate'

group :development, :test do
  gem 'byebug', platforms: [:mri, :mingw, :x64_mingw]
  gem 'sqlite3'
  gem 'bullet' #N+1問題
end

group :development do
  gem 'web-console', '>= 3.3.0'
  gem 'listen', '>= 3.0.5', '< 3.2'
  gem 'spring'
  gem 'spring-watcher-listen', '~> 2.0.0'
  gem 'better_errors'
  gem 'binding_of_caller'
  gem 'derailed_benchmarks' #メモリ容量チェック
  gem 'letter_opener'
  gem 'letter_opener_web', '~> 1.0'
end

group :test do
  gem 'capybara', '>= 2.15'
  gem 'selenium-webdriver'
end

group :production do
  gem 'pg'
  gem 'rails_12factor'
  gem 'heroku-deflater'
  gem 'unicorn'
  gem 'net-http'
end
