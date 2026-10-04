class ListingImagesController < ActionController::Base
  def show
    kind = params[:kind]
    raise ActiveRecord::RecordNotFound unless ListingImage::MOUNTS.key?(kind)
    user = User.publicly_visible.find(params[:id])
    uploader = user.public_send(ListingImage::MOUNTS.fetch(kind))
    raise ActiveRecord::RecordNotFound if uploader.identifier.blank? ||
      params[:fingerprint] != ListingImage.fingerprint(uploader)

    destination = ListingImage.build(user, kind)
    response.headers['X-Content-Type-Options'] = 'nosniff'
    expires_in 1.year, public: true, immutable: true
    send_file destination, type: 'image/jpeg', disposition: 'inline'
  rescue IOError, SystemCallError, MiniMagick::Error, Timeout::Error, SocketError, OpenSSL::SSL::SSLError
    # A transient storage/conversion failure must not break a public image.
    response.headers['Cache-Control'] = 'no-store'
    redirect_to uploader.url, allow_other_host: true
  end
end
