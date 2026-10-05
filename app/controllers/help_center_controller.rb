class HelpCenterController < ApplicationController
  include HelpSubmission
  before_action :private_help_page

  def index
    @query = params[:help_query].to_s.unicode_normalize(:nfkc).strip.first(100)
    @audience = HelpCatalog::AUDIENCES.key?(params[:audience]) ? params[:audience] : 'all'
    @category = HelpCatalog::CATEGORIES.key?(params[:category]) ? params[:category] : nil
    @articles = HelpCatalog.search(query: @query, audience: @audience, category: @category)
    @featured = HelpCatalog::ARTICLES.select { |article| %w[login no-reply contact-circle edit-listing].include?(article[:id]) }
  end

  def show
    @article = HelpCatalog.find(params[:id])
    raise ActiveRecord::RecordNotFound unless @article
  end

  def search
    return unless verify_spam_form!('help-search')
    query = params[:help_query].to_s.unicode_normalize(:nfkc).strip.first(100)
    audience = HelpCatalog::AUDIENCES.key?(params[:audience]) ? params[:audience] : 'all'
    category = HelpCatalog::CATEGORIES.key?(params[:category]) ? params[:category] : nil
    results = HelpCatalog.search(query: query, audience: audience, category: category)
    # Do not store email addresses, URLs or phone-like numbers typed into search.
    safe_query = query.match?(/@|https?:|\d{7,}|(?:\d[ -]?){10,}/i) ? '（個人情報を含む可能性のため記録省略）' : query
    HelpEvent.create!(kind: 'search', query: safe_query, audience: audience, category: category, result_count: results.size,
                      visitor_key: help_visitor_key, recorded_on: Date.current) if query.present?
    redirect_to faq_path(help_query: query, audience: audience, category: category), status: :see_other
  end

  def feedback
    @article = HelpCatalog.find(params[:id])
    raise ActiveRecord::RecordNotFound unless @article
    return unless verify_spam_form!("help-feedback:#{@article[:id]}")
    return head :unprocessable_entity unless %w[helpful unhelpful].include?(params[:answer])
    HelpEvent.transaction do
      HelpEvent.where(visitor_key: help_visitor_key, recorded_on: Date.current, article_id: @article[:id], kind: %w[helpful unhelpful]).delete_all
      HelpEvent.create!(kind: params[:answer], article_id: @article[:id], visitor_key: help_visitor_key, recorded_on: Date.current)
    end
    redirect_to help_article_path(@article[:id]), notice: 'ご回答ありがとうございます。ヘルプの改善に役立てます。', status: :see_other
  rescue ActiveRecord::RecordNotUnique
    redirect_to help_article_path(@article[:id]), notice: 'この回答への評価は本日受付済みです。', status: :see_other
  end
end
