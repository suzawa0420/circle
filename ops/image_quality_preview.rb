# Run with: bundle exec ruby ops/image_quality_preview.rb
# Offline comparison using the real uploader; no Rails boot, DB or remote files.
require 'bundler/setup'
require 'active_support/all'
require 'carrierwave'
require 'carrierwave/processing/mini_magick'
require 'base64'
require 'tmpdir'
require 'json'

module Rails
  def self.env = ActiveSupport::StringInquirer.new('test')
end
require_relative '../app/uploaders/image_uploader'

root = File.expand_path('..', __dir__)
output = File.join(root, 'output/image-quality')
FileUtils.mkdir_p(output)
source = File.join(root, 'public/images/ogp.png')
before_class = Class.new(ImageUploader) do
  self.processors = [[:resize_to_limit, [400, 400], nil, nil],
    [:fix_rotate, [], nil, nil], [:convert, ['jpg'], nil, nil]]
  def fix_rotate
    manipulate! { |image| image.auto_orient; image }
  end
end
model_class = Struct.new(:id, :updated_at)
results = {}
Dir.mktmpdir('image-quality-preview') do |temporary|
  { 'before' => before_class, 'after' => ImageUploader }.each do |label, klass|
    klass.root = temporary
    klass.cache_dir = 'cache'
    uploader = klass.new(model_class.new(1, Time.utc(2026, 11, 3)), :image_01)
    File.open(source) { |file| uploader.store!(file) }
    image = MiniMagick::Image.open(uploader.path)
    results[label] = { dimensions: image.dimensions, bytes: File.size(uploader.path) }
    FileUtils.cp(uploader.path, File.join(output, "#{label}.jpg"))
  end
end
sections = results.map do |label, values|
  title = label == 'before' ? '変更前：長辺400px' : '変更後：長辺1200px以内'
  data = Base64.strict_encode64(File.binread(File.join(output, "#{label}.jpg")))
  <<~HTML
    <section><h2>#{title}</h2><p>#{values[:dimensions].join(' × ')}px ／ #{(values[:bytes] / 1024.0).round(1)} KB</p>
    <img src="data:image/jpeg;base64,#{data}" alt="#{title}のサークルブック画像"></section>
  HTML
end.join
File.write(File.join(output, 'comparison.html'), <<~HTML)
  <!doctype html><html lang="ja"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
  <title>サークルブック 画像品質比較</title><style>
  *{box-sizing:border-box}body{margin:0;padding:24px 16px;background:#f4f7f7;color:#25343b;font:16px/1.7 system-ui,sans-serif}
  main{max-width:1008px;margin:auto}h1{font-size:clamp(22px,4vw,30px)}h2{font-size:20px;margin:0}p{margin:8px 0 16px}
  section{padding:24px;background:white;border:1px solid #d9e3e3;border-radius:12px;margin:24px 0}img{display:block;width:100%;height:auto}
  @media(max-width:600px){body{padding:16px}section{padding:12px;margin:16px 0}h2{font-size:18px}}
  </style><main><h1>サークルブック 画像品質比較</h1>
  <p>同じ元画像を変更前後のアップロード処理で保存した比較です。画面幅に合わせて表示します。</p>
  <p>元画像は既存の1200 × 630pxのサイト画像です。小さな画像は拡大保存しません。既に400pxで保存された写真の細部は戻らないため、元画像の再アップロードが必要です。</p>
  #{sections}</main></html>
HTML
File.write(File.join(output, 'metrics.json'), JSON.pretty_generate(results))
puts JSON.pretty_generate(results)
puts File.join(output, 'comparison.html')
