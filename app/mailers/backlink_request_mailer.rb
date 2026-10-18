class BacklinkRequestMailer < ApplicationMailer
  self.delivery_job = BacklinkRequestDeliveryJob

  def submitted(request)
    @request = request
    mail to: 'circlebook26@gmail.com', subject: '【サークルブック】リンク設置のレベル特典申請が届きました'
  end
end
