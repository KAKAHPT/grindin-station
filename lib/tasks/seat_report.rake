# frozen_string_literal: true

namespace :grindin do
  desc "Regenerate config/seat_fairness.json (the public /fairness page): 50 tournaments of 50-60 players per " \
       "round count (3, 5, 6, 7), fair seating against random, SEAT_REPORT_SEED=2026"
  task seat_report: :environment do
    rounds_list = [3, 5, 6, 7]
    per = 50
    rng = Random.new((ENV["SEAT_REPORT_SEED"] || 2026).to_i)
    report = rounds_list.index_with { |rounds| Grindin::SeatReport.new(rounds: rounds, per: per, rng: rng).call }
    path = Rails.root.join("config/seat_fairness.json")
    path.write(JSON.pretty_generate({ "generated_on" => Date.current.iso8601, "tournaments_per_rounds" => per,
                                      "players" => [50, 60], "rounds" => report }) + "\n")
    puts "wrote #{path}"
    report.each do |rounds, data|
      puts "#{rounds} rounds: fair spread<=1 #{data[:fair][:fair_rate]}% never1 #{data[:fair][:never_first]}% | " \
           "random #{data[:random][:fair_rate]}% never1 #{data[:random][:never_first]}%"
    end
  end
end
