require 'test_helper'
require_relative '../support/chat_records'

class PublicStructuredDataCoverageTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    Rails.cache.clear
    SearchResultCountCache::STORE.clear
    create_chat_records
    @circle.update!(recruitment: '初参加も歓迎します', cost: '1回1,000円')
    @circle.event.update!(txt: 'バスケサークル', place: 1, matching: 1)
    @blog = @circle.blogs.create!(title: '体育館での活動報告', content: '<p>練習会の活動報告です。</p>' * 15)
    @matching = Match.create!(user: @circle, recruit: '募集中', comment: '練習試合の相手を募集します。')
    city = City.create!(name: '渋谷区', city_kana: 'schema-shibuya', prefecture: @circle.prefecture)
    @place = Place.create!(name: '構造化検証体育館', prefecture: @circle.prefecture, city: city,
      events: [@circle.event], address: '渋谷区1-2-3', tag: '1')
    @schedule = @circle.schedules.create!(day: (Date.current + 1).iso8601, title: '公開練習会',
      venue: '公開の体育館', time_s: '10:00', time_e: '12:00', cost: '1,000円',
      note: '運動靴を持参してください。', member_venue: '非公開の集合案内', venue_address: '非公開の住所')
  end

  test 'all five public directories describe the visible collection with canonical destinations' do
    [circles_path, '/dates', blogs_path, matches_path, '/places'].each do |path|
      get path
      assert_response :success, path
      list = node('ItemList')
      assert_equal 1, nodes.count { |item| item['@type'] == 'ItemList' }, path
      assert_equal 'CollectionPage', list.dig('mainEntityOfPage', '@type')
      assert_equal 'WebSite', list.dig('mainEntityOfPage', 'isPartOf', '@type')
      assert list['itemListElement'].any?, path
      list['itemListElement'].each do |entry|
        destination = entry['url'] || entry.dig('item', 'url')
        assert_match %r{\Ahttps://circle-book\.com/}, destination
        assert_operator entry['position'], :>=, 1
      end
    end
  end

  test 'blog detail has an article author visible dates and escaped content while private posts have no article' do
    text = '活動報告 </script><script id="schema-injected">注意</script>'
    @blog.update_columns(title: text)
    get circle_blog_path(@circle, @blog)
    article = node('BlogPosting')
    assert_equal text, article['headline']
    assert_equal @circle.name, article.dig('author', 'name')
    assert_equal "https://circle-book.com#{circle_path(@circle)}", article.dig('author', 'url')
    assert_equal @blog.created_at.iso8601, article['datePublished']
    assert_equal @blog.updated_at.iso8601, article['dateModified']
    assert_select 'script#schema-injected', count: 0
    @blog.update_columns(moderation_status: 'review')
    login_owner
    get circle_blog_path(@circle, @blog)
    assert_response :success
    assert_select 'meta[name=robots][content*=noindex]'
    assert_empty nodes.select { |data| data['@type'] == 'BlogPosting' }
  end

  test 'filtered and legacy lists have one schema for the same displayed population' do
    group = Group.create!(name: '社会人')
    age = Age.create!(name: '20代', decade: 20)
    UsersGroup.create!(user: @circle, group: group)
    UsersAge.create!(user: @circle, age: age)
    tag = Tag.create!(name: '20代', text: '20代を募集中の')
    UserTag.create!(user: @circle, tag: tag)
    paths = [CircleFilterLanding.path(event: @circle.event, prefecture: @circle.prefecture, group: group, age: age),
      "/prefectures/#{@circle.prefecture.kana}/tag/#{tag.id}", "/places/#{@circle.event.ruby}",
      blogs_event_prefecture_path(@circle.event.ruby, @circle.prefecture.kana),
      "/match/#{@circle.event.ruby}/#{@circle.prefecture.kana}"]
    paths.each do |path|
      get path
      assert_response :success, path
      assert_equal 1, nodes.count { |item| item['@type'] == 'ItemList' }, path
      assert_equal 1, node('ItemList')['itemListElement'].length
    end
  end

  test 'hidden circles and reviews and visually suppressed FAQ do not acquire public markup' do
    @circle.questions.create!(content: '参加できますか', answer: 'はい、参加できます。')
    @circle.reviews.create!(review: 1, comment: '非公開団体の口コミです。')
    @circle.update_columns(review_permit: false)
    get circle_path(@circle)
    assert_empty nodes.select { |data| data['@type'] == 'FAQPage' }
    @circle.update_columns(publication_status: 'draft')
    get '/reviews'
    assert_response :success
    assert_empty nodes.select { |data| data['@type'] == 'ItemList' }
    refute_includes response.body, '非公開団体の口コミです。'
    login_owner
    get circle_path(@circle)
    assert_response :success
    assert_empty nodes
  end

  test 'paginated blog lists include only displayed public posts with continuous positions' do
    now = Time.current
    Blog.insert_all!(11.times.map do |i|
      { user_id: @circle.id, title: "活動報告#{i}", content: '実際の活動についての報告です。' * 15,
        moderation_status: 'clear', created_at: now + i, updated_at: now + i }
    end)
    @blog.update_columns(moderation_status: 'blocked')
    get blogs_path, params: { page: '2' }
    list = node('ItemList')
    assert_equal 11, list['itemListElement'].first['position']
    assert_equal 1, list['itemListElement'].size
    assert_equal "https://circle-book.com/blogs?page=2", list['url']
    refute_includes list.to_json, circle_blog_path(@circle, @blog)
  end

  test 'owner answered questions do not masquerade as community QAPage or fabricate answers' do
    answered = @circle.questions.create!(content: '初参加でも大丈夫ですか', answer: 'はい、参加できます。')
    pending = @circle.questions.create!(content: '次回の集合場所を教えてください')
    get circle_path(@circle)
    faq = node('FAQPage')
    assert_equal [answered.content], faq['mainEntity'].map { |item| item['name'] }
    get user_question_path(@circle, answered)
    page = node('WebPage')
    assert_equal 'Question', page.dig('mainEntity', '@type')
    assert_equal answered.answer, page.dig('mainEntity', 'acceptedAnswer', 'text')
    assert_select '#answer', text: /参加できます/
    assert_empty nodes.select { |data| data['@type'] == 'QAPage' }
    get user_question_path(@circle, pending)
    refute node('WebPage')['mainEntity'].key?('acceptedAnswer')
    get user_questions_path(@circle)
    assert_equal 2, node('ItemList')['itemListElement'].length
  end

  test 'circle and review pages identify the organization and use real binary review scores and nicknames' do
    review = @circle.reviews.create!(review: 1, nickname: '参加者あお', comment: '楽しく参加できました。')
    @circle.update_columns(review_score: '5')
    [circle_path(@circle), user_reviews_path(@circle)].each do |path|
      get path
      org = node('Organization')
      assert_equal "https://circle-book.com#{circle_path(@circle)}#organization", org['@id']
      assert_equal '参加者あお', org['review'].first.dig('author', 'name')
      assert_equal 1, org['review'].first.dig('reviewRating', 'ratingValue')
      assert_equal 1, org['aggregateRating']['reviewCount']
      assert_select "#review-#{review.id}"
      refute org.key?('priceRange')
    end
    get '/reviews'
    assert_response :success
    assert_equal 'Review', node('ItemList')['itemListElement'].first.dig('item', '@type')
  end

  test 'facilities publish the same overall rating as the HTML and exclude private reviews' do
    @place.place_reviews.create!(price: 4, facility: 4, access: 4, reservation: 4, average_score: 4,
      comment: '使いやすい体育館でした。')
    @place.place_reviews.create!(price: 1, facility: 1, access: 1, reservation: 1, average_score: 1,
      comment: '非公開の口コミです。', moderation_status: 'blocked')
    @place.update_columns(average_score: 4)
    get place_listing_path_for_test
    facility = node('LocalBusiness')
    assert_equal 'https://schema.org/SportsActivityLocation', facility['additionalType']
    assert_equal 1, facility['aggregateRating']['reviewCount']
    assert_equal 4, facility['aggregateRating']['ratingValue']
    assert_select '#place-reviews-title', text: '口コミ・評価'
    assert_includes response.body, '総合評価：'
    refute_includes facility.to_json, '非公開'
    refute facility.key?('image'), 'A generic sport illustration is not a facility photograph'
  end

  test 'events have exact offers only for unambiguous prices and never expose members only fields' do
    get user_schedule_path(@circle, @schedule)
    event = node('Event')
    assert_equal 1000, event.dig('offers', 'price')
    assert_equal 'JPY', event.dig('offers', 'priceCurrency')
    refute_includes event.to_json, '非公開'
    @schedule.update!(cost: '男性1,000円・女性500円')
    get user_schedule_path(@circle, @schedule)
    refute node('Event').key?('offers')
    @schedule.update!(cost: '無料', recruitment: '募集終了')
    get user_schedule_path(@circle, @schedule)
    assert_equal 0, node('Event').dig('offers', 'price')
    assert_equal 'https://schema.org/SoldOut', node('Event').dig('offers', 'availability')
    @schedule.update!(time_s: nil)
    get user_schedule_path(@circle, @schedule)
    assert_empty nodes.select { |data| data['@type'] == 'Event' }
    assert_equal @schedule.title, node('WebPage')['name']
  end

  test 'practice match recruitment stays a web page instead of inventing an event date' do
    get match_path(@circle)
    page = node('WebPage')
    assert_equal @matching.comment, page['description']
    assert_equal 'Organization', page.dig('about', '@type')
    assert_empty nodes.select { |data| %w[Event SportsEvent].include?(data['@type']) }
  end

  private

  def nodes
    css_select('script[type="application/ld+json"]').flat_map do |script|
      data = JSON.parse(script.text)
      data['@graph'] || [data]
    end
  end

  def node(type)
    nodes.find { |data| data['@type'] == type }.tap { |data| assert data, "Missing #{type}" }
  end

  def login_owner
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
  end

  def place_listing_path_for_test
    "/places/#{@circle.event.ruby}/#{@circle.prefecture.kana}/#{@place.city.city_kana}/#{@place.id}"
  end
end
