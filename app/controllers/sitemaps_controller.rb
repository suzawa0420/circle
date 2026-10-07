# Sitemap responses must not run account redirects or database-backed page filters.
class SitemapsController < ActionController::Base
  def index
    serve('sitemap')
  end

  def show
    serve(params[:name].to_s)
  end

  private

  def serve(name)
    xml = Rails.cache.fetch("published-sitemap-v2/#{name}", expires_in: 5.minutes) do
      PublishedSitemap.fetch(name)
    end
    expires_in 5.minutes, public: true
    render body: xml, content_type: 'application/xml; charset=utf-8'
  rescue PublishedSitemap::NotFound
    head :not_found
  rescue PublishedSitemap::Unavailable
    response.headers['Cache-Control'] = 'no-store'
    response.headers['Retry-After'] = '300'
    head :service_unavailable
  end
end
