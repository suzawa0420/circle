class ImageUploader < CarrierWave::Uploader::Base

  include CarrierWave::MiniMagick
  # Detail photos fill up to 960 CSS pixels on desktop (2x displays).
  # Avatars stay smaller so lists do not download full-size detail photos.
  AVATAR_MOUNTS = %i[pic_profile image_profile profile_img icon].freeze
  MAX_PIXELS = 60_000_000

  process :normalize_image

  def normalize_image
    manipulate! do |image|
      raise CarrierWave::ProcessingError, '画像のサイズが大きすぎます。' if image.width * image.height > MAX_PIXELS

      edge = AVATAR_MOUNTS.include?(mounted_as&.to_sym) ? 640 : 1920
      image.auto_orient
      image.resize "#{edge}x#{edge}>"
      image.strip
      image.format 'jpg'
      image.quality '88'
      image.interlace 'Plane'
      image
    end
  end

  if Rails.env.development?
    storage :file
  elsif Rails.env.test?
    storage :file
  else
    storage :fog
  end

  # Override the directory where uploaded files will be stored.
  # This is a sensible default for uploaders that are meant to be mounted:
  def store_dir
    "uploads/#{model.class.to_s.underscore}/#{mounted_as}/#{model.id}"
  end

  def default_url(*_args)
    "/images/" + [version_name, "default.png"].compact.join('_')
  end

  # A retrieved S3 file represents the identifier already stored in the DB.
  # CarrierWave 3's Fog file presence check performs HEAD; never do that while
  # rendering a page. Keep local/cached upload validation semantics unchanged.
  def blank?
    return false if file.is_a?(CarrierWave::Storage::Fog::File)

    super
  end

  # Provide a default URL as a default if there hasn't been a file uploaded:
  # def default_url(*args)
  #   # For Rails 3.1+ asset pipeline compatibility:
  #   # ActionController::Base.helpers.asset_path("fallback/" + [version_name, "default.png"].compact.join('_'))
  #
  #   "/images/fallback/" + [version_name, "default.png"].compact.join('_')
  # end

  # Process files as they are uploaded:
  # process scale: [200, 300]
  #
  # def scale(width, height)
  #   # do something
  # end

  # Create different versions of your uploaded files:
  # version :thumb do
  #   process resize_to_fit: [50, 50]
  # end

  # Add a white list of extensions which are allowed to be uploaded.
  # For images you might use something like this:

  # jpg, jpeg, gif, png のみ許可する
  def extension_allowlist
    %w(jpg jpeg gif png HEIC HEIF heic heif)
  end

  # CarrierWave 3 otherwise rewrites retrieved legacy .png/.jpeg keys to .jpg.
  # New uploads already receive a .jpg filename below; preserve stored keys.
  force_extension false

  # 20MB以下
  def size_range
    1..20.megabytes
  end

  # CarrierWave 3 may clear original_filename after storing. The processor
  # always writes JPEG, so keep the stored identifier stable and explicit.
  def filename
    "#{secure_token}.jpg" if file
  end

  # Keep long-lived S3 caching, but make a changed record resolve to a fresh URL.
  # Preserve CarrierWave's no-argument, options and version call signatures.
  def url(*args)
    image_url = super
    # Fog::File#empty? performs a remote HEAD request. URL generation only
    # needs the mounted file reference, not a network existence check.
    return image_url if image_url.blank? || file.nil? || model&.updated_at.blank?

    separator = image_url.include?("?") ? "&" : "?"
    "#{image_url}#{separator}v=#{model.updated_at.utc.to_i}"
  end

  protected
  def secure_token
    var = :"@#{mounted_as}_secure_token"
    model.instance_variable_get(var) or model.instance_variable_set(var, SecureRandom.uuid)
  end


end
