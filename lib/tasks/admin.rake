# frozen_string_literal: true

namespace :grindin do
  desc "Make the user with this email a site admin: rails grindin:admin[email]"
  task :admin, [:email] => :environment do |_, args|
    user = User.find_by(email_address: args[:email].to_s.strip.downcase) || abort("No user with that email.")
    user.update!(admin: true)
    puts "#{user.email_address} is now an admin."
  end

  namespace :admin do
    desc "Remove site admin from the user with this email: rails grindin:admin:revoke[email]"
    task :revoke, [:email] => :environment do |_, args|
      user = User.find_by(email_address: args[:email].to_s.strip.downcase) || abort("No user with that email.")
      user.update!(admin: false)
      puts "#{user.email_address} is no longer an admin."
    end
  end
end
