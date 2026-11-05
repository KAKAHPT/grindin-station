# frozen_string_literal: true

namespace :rankings do
  desc "Rebuild ranking points and Elo ratings from every finished event"
  task rebuild: :environment do
    outcome = Rankings::Rebuild.call
    puts "Rankings rebuilt at #{outcome[:at].iso8601}: #{outcome[:contributions]} contributions, " \
         "#{outcome[:ratings]} ratings."
  end
end
