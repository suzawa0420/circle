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
  end

  teardown do
    @circle.pic_profile.remove!
    @source.close!
    FileUtils.rm_f([@destination, "#{@destination}.lock"])
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
      get @url
      assert_redirected_to @circle.pic_profile.url
      assert_equal 'no-store', response.headers['Cache-Control']
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
end
