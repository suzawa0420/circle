require Rails.root.join('lib/registration_turnstile')

RegistrationTurnstile.load_configuration(
  production: Rails.env.production?,
  path: File.expand_path('~/.config/circle/turnstile.json')
)
