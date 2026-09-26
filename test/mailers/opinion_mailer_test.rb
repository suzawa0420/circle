require 'test_helper'

class OpinionMailerTest < ActionMailer::TestCase
  test "send_opinion" do
    mail = OpinionMailer.send_opinion(opinions(:one), users(:one))
    assert_equal "【サークルブック】ご意見箱に投稿がありました！", mail.subject
    assert_equal ["circlebook26@gmail.com"], mail.to
    assert_equal ["noreply@circle-book.com"], mail.from
    assert_equal ["admin-one@example.com"], mail.reply_to
  end

end
