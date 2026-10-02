# Configure sensitive parameters filtered from request logs.
Rails.application.config.filter_parameters += [:password, :'cf-turnstile-response', :turnstile_secret_key, :spam_form_token, :contact_website]

Rails.application.config.filter_parameters += [:token, :body, :comment, :reason, :message, :evaluation, :report]

Rails.application.config.filter_parameters += [:date_of_birth]
