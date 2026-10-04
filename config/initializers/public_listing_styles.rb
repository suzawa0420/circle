require Rails.root.join('lib/public_listing_styles')

Rails.application.config.assets.configure do |environment|
  environment.register_postprocessor 'text/css', PublicListingStyles
end
