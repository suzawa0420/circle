class ListingImagesController < ActionController::Base
  def show
    kind = params[:kind]
    format = params[:format].presence || 'jpg'
    raise ActiveRecord::RecordNotFound unless ListingImage::MOUNTS.key?(kind)
    raise ActiveRecord::RecordNotFound unless ListingImage::CONTENT_TYPES.key?(format)
    user = User.publicly_visible.find(params[:id])
    uploader = user.public_send(ListingImage::MOUNTS.fetch(kind))
    raise ActiveRecord::RecordNotFound if uploader.identifier.blank? ||
      params[:fingerprint] != ListingImage.fingerprint(uploader)

    begin
      destination = ListingImage.build(user, kind, format: format)
      response.headers['X-Content-Type-Options'] = 'nosniff'
      expires_in 1.year, public: true, immutable: true
      send_file destination.to_s, type: ListingImage::CONTENT_TYPES.fetch(format), disposition: 'inline'
    rescue StandardError
      # Keep access/identifier checks outside this boundary. Any storage or
      # conversion failure for an already-public image falls back to its source.
      response.headers['Cache-Control'] = 'no-store'
      redirect_to uploader.url, allow_other_host: true
    end
  end
end
