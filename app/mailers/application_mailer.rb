class ApplicationMailer < ActionMailer::Base
  default from:     "noreply@circle-book.com",
          reply_to: "circlebook26@gmail.com"
  layout 'mailer'
end
