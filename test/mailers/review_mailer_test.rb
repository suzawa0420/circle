require 'test_helper'

class ReviewMailerTest < ActionMailer::TestCase
  test "send_review" do
    mail = ReviewMailer.send_review(users(:one))
    assert_equal "【サークルブック】『MyString』宛に高評価の口コミが投稿されました！", mail.subject
    assert_equal ["admin-one@example.com"], mail.to
    assert_equal ["noreply@circle-book.com"], mail.from
    assert_match "MyString", mail.text_part.body.decoded
  end

end
