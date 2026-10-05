module HelpSubmission
  private

  def private_help_page
    response.headers['Referrer-Policy'] = 'same-origin'
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['X-Robots-Tag'] = 'noindex, nofollow' unless controller_path == 'help_center' && request.get? && params[:help_query].blank? && params[:category].blank? && params[:audience].in?([nil, 'all'])
  end

  def help_visitor_key
    session[:help_visitor_id] ||= SecureRandom.hex(32)
    Digest::SHA256.hexdigest(session[:help_visitor_id])
  end
end
