require 'minitest/autorun'
require_relative '../../app/services/youtube_video'

class YoutubeVideoTest < Minitest::Test
  def test_supported_video_urls
    [
      'https://www.youtube.com/watch?v=Abcde_123-4&feature=shared',
      'https://youtube.com/watch?feature=shared&v=Abcde_123-4',
      'https://m.youtube.com/watch?v=Abcde_123-4',
      'https://youtu.be/Abcde_123-4?si=share',
      'https://www.youtube.com/shorts/Abcde_123-4',
      'https://youtube.com/embed/Abcde_123-4',
      'https://youtube.com/live/Abcde_123-4',
      ' http://youtube.com/watch?v=Abcde_123-4 '
    ].each { |url| assert_equal 'Abcde_123-4', YoutubeVideo.id(url), url }
  end

  def test_rejects_non_video_and_untrusted_urls
    [nil, '', 'invalid', 'javascript:alert(1)', '//youtu.be/Abcde_123-4',
     'https://youtube.com.evil.test/watch?v=Abcde_123-4',
     'https://youtube.com@evil.test/watch?v=Abcde_123-4',
     'https://evil.test@youtube.com/watch?v=Abcde_123-4',
     'https://youtu.be:444/Abcde_123-4',
     'https://youtube.com/playlist?list=Abcde_123-4',
     'https://youtube.com/@channel', 'https://youtu.be/short',
     'https://youtu.be/Abcde_123-4/extra',
     'https://youtube.com/watch?v=%22%3E%3Cscript%3E',
     'https://youtube.com/watch?v=%FF'].each { |url| assert_nil YoutubeVideo.id(url), url.inspect }
  end
end
