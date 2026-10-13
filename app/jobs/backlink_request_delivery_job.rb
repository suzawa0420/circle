class BacklinkRequestDeliveryJob < ActionMailer::MailDeliveryJob
  self.enqueue_after_transaction_commit = true
  retry_on StandardError, wait: :polynomially_longer, attempts: 5
end
