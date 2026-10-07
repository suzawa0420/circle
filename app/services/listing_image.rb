require 'digest'
require 'net/http'
require 'tempfile'
require 'uri'

# Read-only derivatives of existing uploads. Originals and DB identifiers stay
# intact; each server keeps its own atomic disk cache across deployments.
class ListingImage
  SIZES = { 'profile' => [160, 160], 'header' => [400, 160] }.freeze
  MOUNTS = { 'profile' => :pic_profile, 'header' => :pic_header }.freeze
  CONTENT_TYPES = { 'jpg' => 'image/jpeg', 'webp' => 'image/webp' }.freeze
  MAX_BYTES = 20.megabytes

  def self.fingerprint(uploader)
    Digest::SHA256.hexdigest(uploader.identifier.to_s)[0, 24]
  end

  def self.path(user, kind, format: 'jpg')
    CONTENT_TYPES.fetch(format)
    uploader = user.public_send(MOUNTS.fetch(kind))
    Rails.root.join('tmp/cache/listing_images', "#{user.id}-#{kind}-#{fingerprint(uploader)}.#{format}")
  end

  def self.build(user, kind, format: 'jpg')
    uploader = user.public_send(MOUNTS.fetch(kind))
    destination = path(user, kind, format: format)
    FileUtils.mkdir_p(destination.dirname)
    File.open("#{destination}.lock", File::RDWR | File::CREAT, 0o600) do |lock|
      lock.flock(File::LOCK_EX)
      return destination if File.file?(destination)

      Tempfile.create(['listing-source', '.jpg']) do |source|
        source.binmode
        jpeg_cache = path(user, kind)
        if format == 'webp' && File.file?(jpeg_cache)
          # Reuse existing bounded derivatives during rollout, avoiding a new
          # remote download for every already-cached photograph.
          File.open(jpeg_cache, 'rb') { |file| IO.copy_stream(file, source, MAX_BYTES + 1) }
        elsif uploader.file.is_a?(CarrierWave::Storage::Fog::File)
          download(uploader.url, source)
        else
          File.open(uploader.file.path, 'rb') { |file| IO.copy_stream(file, source, MAX_BYTES + 1) }
        end
        source.flush
        raise IOError, 'Image exceeds limit' if source.size > MAX_BYTES
        image = MiniMagick::Image.open(source.path)
        raise IOError, 'Unsupported image' unless %w[JPEG PNG GIF].include?(image.type)
        raise IOError, 'Oversized image' if image.width > 4096 || image.height > 4096
        image.collapse! if image.type == 'GIF'
        width, height = SIZES.fetch(kind)
        Tempfile.create(['listing-result', ".#{format}"], destination.dirname) do |output|
          output.binmode
          # Resize before encoding in one pass, avoiding an intermediate lossy
          # conversion of the full-resolution source.
          MiniMagick::Tool::Convert.new do |command|
            command << image.path
            command.auto_orient
            command.thumbnail "#{width}x#{height}^"
            command.gravity 'center'
            command.extent "#{width}x#{height}"
            command.strip
            command.quality '78'
            command.interlace 'Plane' if format == 'jpg'
            command << "#{format}:#{output.path}"
          end
          File.rename(output.path, destination)
        end
      end
    end
    destination
  end

  def self.download(url, output)
    output.binmode
    uri = URI(url)
    # Never proxy an arbitrary URL, redirect, private endpoint or user input.
    raise IOError, 'Unexpected image origin' unless uri.scheme == 'https' &&
      uri.host == 'circlebook.s3.ap-northeast-1.amazonaws.com' && uri.port == 443 &&
      uri.path.start_with?('/uploads/user/') && uri.userinfo.nil?

    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 3, read_timeout: 5) do |http|
      http.request(Net::HTTP::Get.new(uri.request_uri)) do |response|
        raise IOError, 'Image unavailable' unless response.is_a?(Net::HTTPSuccess)
        raise IOError, 'Image exceeds limit' if response['content-length'].to_i > MAX_BYTES
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        bytes = 0
        response.read_body do |chunk|
          raise IOError, 'Image download timeout' if Process.clock_gettime(Process::CLOCK_MONOTONIC) - started > 8
          bytes += chunk.bytesize
          raise IOError, 'Image exceeds limit' if bytes > MAX_BYTES
          output.write(chunk)
        end
      end
    end
  end
end
