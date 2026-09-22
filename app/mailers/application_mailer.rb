class ApplicationMailer < ActionMailer::Base
  default from:     "noreply@circle-book.com",
          bcc:      "circlebook26@gmail.com",
          reply_to: "circlebook26@gmail.com"
  layout 'mailer'
end
