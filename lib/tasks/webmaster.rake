namespace :webmaster do
  desc 'Create the single webmaster account using an interactive prompt (no public signup)'
  task setup: :environment do
    require 'io/console'
    abort 'ウェブマスターは作成済みです。' if Webmaster.exists?
    abort '対話可能な端末で実行してください。' unless $stdin.tty?
    print 'メールアドレス: '
    email = $stdin.gets.to_s.strip
    print 'パスワード（12文字以上）: '
    password = $stdin.noecho(&:gets).to_s.chomp
    puts
    print 'パスワード（確認）: '
    confirmation = $stdin.noecho(&:gets).to_s.chomp
    puts
    account = Webmaster.new(id: 1, email: email, password: password, password_confirmation: confirmation)
    if account.save
      puts 'ウェブマスターを作成しました。/webmaster/login からログインできます。'
    else
      puts account.errors.full_messages.join("\n")
      abort '作成できませんでした。'
    end
  end
end
