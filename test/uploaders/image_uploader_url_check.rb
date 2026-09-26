# Isolated regression test: no Rails boot, database, credentials or S3 access.
require 'bundler/setup'
require 'minitest/autorun'
require 'active_support/all'
require 'carrierwave'
require 'carrierwave/processing/mini_magick'

module Rails
  def self.env
    ActiveSupport::StringInquirer.new('test')
  end
end

require_relative '../../app/uploaders/image_uploader'

class ImageUploaderUrlTest < Minitest::Test
  Model = Struct.new(:id, :updated_at)
  FakeFile = Struct.new(:location, :received_options) do
    def empty?
      raise 'URL generation must not check remote file existence'
    end

    def url(options = {})
      self.received_options = options
      location
    end
  end

  def uploader(file_url = nil, updated_at = Time.utc(2026, 9, 25))
    result = ImageUploader.new(Model.new(1, updated_at), :pic_profile)
    result.instance_variable_set(:@file, FakeFile.new(file_url)) if file_url
    result
  end

  def test_missing_image_uses_default_without_arguments
    assert_equal '/images/default.png', uploader.url
    assert_equal '/images/default.png', uploader.to_s
  end

  def test_missing_image_accepts_explicit_options
    assert_equal '/images/default.png', uploader.url({})
    assert_equal '/images/default.png', uploader.url(expires: 60)
  end

  def test_uploaded_image_retains_cache_version
    assert_equal '/uploads/example.jpg?v=1790294400', uploader('/uploads/example.jpg').url
    assert_equal '/uploads/example.jpg?x=1&v=1790294400', uploader('/uploads/example.jpg?x=1').url
  end

  def test_storage_options_are_forwarded
    instance = uploader('/uploads/example.jpg')
    instance.url(expires: 60)
    assert_equal({ expires: 60 }, instance.file.received_options)
  end

  def test_filename_does_not_check_remote_file_existence
    assert_match(/\A[0-9a-f-]+\.jpg\z/, uploader('/uploads/example.jpg').filename)
  end

  def test_stored_fog_file_presence_does_not_access_s3
    instance = uploader
    remote_file = CarrierWave::Storage::Fog::File.new(instance, Object.new, 'uploads/example.jpg')
    def remote_file.empty?
      raise 'Stored image presence must not access S3'
    end
    instance.instance_variable_set(:@file, remote_file)
    assert instance.present?
    refute instance.blank?
    assert uploader.blank?
  end

  def test_local_file_presence_keeps_empty_file_semantics
    instance = uploader
    local_file = Struct.new(:empty) { def empty? = empty }.new(true)
    instance.instance_variable_set(:@file, local_file)
    assert instance.blank?
    local_file.empty = false
    assert instance.present?
  end

  def test_missing_timestamp_keeps_original_url
    assert_equal '/uploads/example.jpg', uploader('/uploads/example.jpg', nil).url
  end

  def test_version_and_options_are_forwarded
    versioned = Class.new(ImageUploader) { version(:thumb) }
    instance = versioned.new(Model.new(1, Time.utc(2026, 9, 25)), :pic_profile)
    assert_equal '/images/thumb_default.png', instance.url(:thumb)
    assert_equal '/images/thumb_default.png', instance.url(:thumb, expires: 60)
  end
end
