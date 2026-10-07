# Chat attachments never use the public profile-image URLs or cache directory.
class ChatImageUploader < CarrierWave::Uploader::Base
  include CarrierWave::MiniMagick

  storage(Rails.env.production? ? :fog : :file)
  cache_storage :file
  def root = Rails.root.join('storage').to_s
  def cache_dir = Rails.root.join('tmp', 'private-chat-images').to_s
  def store_dir = "private/chat-images/#{model.id}"
  def fog_public = false
  def asset_host = nil
  def fog_attributes = { 'Cache-Control' => 'private, no-store' }
  def extension_allowlist = %w[jpg jpeg png webp heic heif]
  def content_type_allowlist = /\Aimage\/(jpeg|png|webp|heic|heif)\z/
  def size_range = 1..10.megabytes

  process :normalize_image
  process :encrypt_image

  def filename
    @chat_filename ||= "#{SecureRandom.uuid}.bin"
  end

  def blank?
    return false if file.is_a?(CarrierWave::Storage::Fog::File)
    super
  end

  def decrypted_image
    self.class.encryptor.decrypt_and_verify(read)
  end

  # Also protects attachments if the existing media bucket has a public policy.
  def self.encryptor
    key = Rails.application.key_generator.generate_key('chat-image-v1', 32)
    ActiveSupport::MessageEncryptor.new(key, cipher: 'aes-256-gcm', serializer: ActiveSupport::MessageEncryptor::NullSerializer)
  end

  private

  def normalize_image
    manipulate! do |image|
      raise CarrierWave::ProcessingError, '画像のサイズが大きすぎます。' if image.width * image.height > 60_000_000
      image.auto_orient
      image.resize '2048x2048>'
      image.strip
      image.format 'jpg'
      image.quality '90'
      image
    end
  end

  def encrypt_image
    File.binwrite(current_path, self.class.encryptor.encrypt_and_sign(File.binread(current_path)))
  end
end
