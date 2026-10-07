require 'test_helper'
require_relative '../support/chat_records'
require 'base64'
require 'tempfile'
require 'minitest/mock'

class ListingImagesTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    @source = Tempfile.new(['listing-image', '.gif'])
    @source.binmode
    @source.write(Base64.decode64('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'))
    @source.rewind
    @circle.pic_profile = @source
    @circle.save!
    @url = listing_image_path(kind: 'profile', id: @circle.id, fingerprint: ListingImage.fingerprint(@circle.pic_profile))
    @destination = ListingImage.path(@circle, 'profile')
    @webp_destination = ListingImage.path(@circle, 'profile', format: 'webp')
  end

  teardown do
    if @header_destination
      @circle.pic_header.remove!
      FileUtils.rm_f([@header_destination, "#{@header_destination}.lock"])
    end
    @circle.pic_profile.remove!
    @source.close!
    FileUtils.rm_f([@destination, "#{@destination}.lock"])
    FileUtils.rm_f([@webp_destination, "#{@webp_destination}.lock"])
  end

  test 'uploaded leading photograph is preloaded at its displayed WebP URL' do
    SearchResultCountCache::STORE.clear
    @source.rewind
    @circle.pic_header = @source
    @circle.save!
    @header_destination = ListingImage.path(@circle, 'header', format: 'webp')
    get event_prefecture_path(@circle.event.ruby, @circle.prefecture.kana)
    assert_response :success
    expected_url = listing_image_path(kind: 'header', id: @circle.id,
      fingerprint: ListingImage.fingerprint(@circle.pic_header), format: 'webp')
    assert_select 'img.header_imege_user_list[loading=eager][src=?]', expected_url, count: 1
    assert_select 'link[rel=preload][as=image][href=?]', expected_url, count: 1
    get expected_url
    assert_response :success
    assert_equal 'image/webp', response.media_type
    assert_equal [400, 160], MiniMagick::Image.open(@header_destination).dimensions
  end

  test 'webp derivatives have separate immutable URLs and reuse the cached JPEG without fetching the original' do
    get @url
    assert_response :success
    jpeg_bytes = File.binread(@destination)
    webp_url = listing_image_path(kind: 'profile', id: @circle.id,
      fingerprint: ListingImage.fingerprint(@circle.pic_profile), format: 'webp')
    refute_equal @url, webp_url
    # A warm JPEG must suffice even if the original storage is unavailable.
    ListingImage.stub(:download, ->(*) { flunk 'Cached JPEG should avoid a remote download' }) do
      FileUtils.mv(@circle.pic_profile.path, "#{@circle.pic_profile.path}.backup")
      begin
        get webp_url
      ensure
        FileUtils.mv("#{@circle.pic_profile.path}.backup", @circle.pic_profile.path)
      end
    end
    assert_response :success
    assert_equal 'image/webp', response.media_type
    assert_match(/immutable/, response.headers['Cache-Control'])
    assert_equal [160, 160], MiniMagick::Image.open(@webp_destination).dimensions
    assert_equal 'WEBP', MiniMagick::Image.open(@webp_destination).type
    assert_equal jpeg_bytes, File.binread(@destination)
    timestamp = File.mtime(@webp_destination)
    get webp_url
    assert_equal timestamp, File.mtime(@webp_destination)
    @circle.update_columns(publication_status: 'draft')
    assert_raises(ActiveRecord::RecordNotFound) { get webp_url }
  end

  test 'cold webp conversion preserves the original and rejects stale fingerprints' do
    original = File.binread(@circle.pic_profile.path)
    webp_url = @url.sub(/\.jpg\z/, '.webp')
    get webp_url
    assert_response :success
    assert_equal 'image/webp', response.media_type
    assert_equal original, File.binread(@circle.pic_profile.path)
    refute File.exist?(@destination)
    assert_raises(ActiveRecord::RecordNotFound) { get webp_url.sub(ListingImage.fingerprint(@circle.pic_profile), '0' * 24) }
  end

  test 'bounded derivative keeps the original and caches independently of text edits' do
    original = @circle.pic_profile.path
    get @url
    assert_response :success
    assert_equal 'image/jpeg', response.media_type
    assert_match(/public/, response.headers['Cache-Control'])
    assert_match(/immutable/, response.headers['Cache-Control'])
    assert_equal [160, 160], MiniMagick::Image.open(@destination).dimensions
    assert_equal [1, 1], MiniMagick::Image.open(original).dimensions
    timestamp = File.mtime(@destination)
    @circle.update!(name: '画像変更なし')
    get @url
    assert_response :success
    assert_equal timestamp, File.mtime(@destination)
  end

  test 'stale fingerprints and unpublished circles cannot produce derivatives' do
    assert_raises(ActiveRecord::RecordNotFound) { get @url.sub(ListingImage.fingerprint(@circle.pic_profile), '0' * 24) }
    @circle.update_columns(publication_status: 'draft')
    assert_raises(ActiveRecord::RecordNotFound) { get @url }
    refute File.exist?(@destination)
  end

  test 'conversion failure falls back to the original without caching the failure' do
    ListingImage.stub(:build, ->(*) { raise RuntimeError, 'synthetic failure' }) do
      [@url, @url.sub(/\.jpg\z/, '.webp')].each do |url|
        get url
        assert_redirected_to @circle.pic_profile.url
        assert_equal 'no-store', response.headers['Cache-Control']
      end
    end
  end

  test 'image downloads reject redirects and arbitrary origins before networking' do
    Tempfile.create('listing-blocked') do |file|
      %w[http://127.0.0.1/uploads/user/a https://example.test/uploads/user/a
        https://circlebook.s3.ap-northeast-1.amazonaws.com/private/a].each do |url|
        assert_raises(IOError) { ListingImage.download(url, file) }
      end
    end
  end

  test 'retrieved remote uploads use the bounded downloader and generate a cached derivative' do
    uploader = @circle.pic_profile
    original_path = uploader.path
    remote_file = CarrierWave::Storage::Fog::File.allocate
    downloader = ->(url, output) do
      assert_equal 'https://circlebook.s3.ap-northeast-1.amazonaws.com/uploads/user/profile.jpg', url
      File.open(original_path, 'rb') { |source| IO.copy_stream(source, output) }
    end
    uploader.stub(:file, remote_file) do
      uploader.stub(:url, 'https://circlebook.s3.ap-northeast-1.amazonaws.com/uploads/user/profile.jpg') do
        ListingImage.stub(:download, downloader) do
          assert_equal @destination, ListingImage.build(@circle, 'profile')
          assert_equal [160, 160], MiniMagick::Image.open(@destination).dimensions
        end
      end
    end
  end

  test 'remote JPEG chunks bypass the production default text transcoding' do
    bytes = "\xFF\xD8\xFF\x00".b
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response['content-length'] = bytes.bytesize.to_s
    response.define_singleton_method(:read_body) { |&block| block.call(bytes) }
    http = Object.new
    http.define_singleton_method(:request) { |_request, &block| block.call(response) }
    connect = ->(*_args, **_options, &block) { block.call(http) }
    Tempfile.create('listing-binary') do |output|
      output.set_encoding(Encoding::UTF_8, Encoding::UTF_8)
      Net::HTTP.stub(:start, connect) do
        ListingImage.download('https://circlebook.s3.ap-northeast-1.amazonaws.com/uploads/user/image.jpg', output)
      end
      output.rewind
      assert_equal Encoding::BINARY, output.external_encoding
      assert_equal bytes, output.read
    end
  end
end
