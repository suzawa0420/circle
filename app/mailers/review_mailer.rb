class ReviewMailer < ApplicationMailer

  def send_review(user)
    @user = user
    mail to:      user.admin_user.email,
        subject: "【サークルブック】『#{user.name}』宛に高評価の口コミが投稿されました！"
  end

  def bad_review(user)
    @user = user
    mail to:      "circlebook26@gmail.com",
        subject: "【サークルブック】『#{user.name}』宛に低評価の口コミが投稿されました！"
  end

end
