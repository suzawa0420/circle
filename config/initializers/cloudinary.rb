# Cloudinary's Rails integration rewrites every image asset URL when this is
# enabled. Local development does not have Cloudinary credentials, so keep
# regular Sprockets asset paths outside production.
Cloudinary.config.enhance_image_tag = false unless Rails.env.production?
