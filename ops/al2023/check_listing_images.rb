# Only public image conversion and bounded diagnostic metadata; no DB writes,
# exception messages, credentials, configuration dumps or raw application logs.
begin
  require_relative '../../config/environment'
  user = User.publicly_visible.find(7456)
  image = ListingImage.build(user, 'header')
  puts "LISTING_IMAGE_CHECK=#{JSON.generate(status: 'ok', bytes: File.size(image), dimensions: MiniMagick::Image.open(image).dimensions)}"
rescue StandardError => error
  details = { status: 'error', error_class: error.class.name }
  if error.is_a?(NoMethodError)
    details[:missing_method] = error.name
    details[:receiver_class] = error.receiver.class.name
  end
  details[:code_locations] = error.backtrace.grep(%r{/(app/services/listing_image|app/controllers/listing_images_controller)\.rb:}).map { |line| line.sub(%r{^.*?/(app/)}, '\\1') }.first(4)
  puts "LISTING_IMAGE_CHECK=#{JSON.generate(details)}"
  exit 1
end
