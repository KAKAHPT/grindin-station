# frozen_string_literal: true

namespace :grindin do
  desc "Regenerate config/seat_fairness.json (the public /fairness page): 500 real tournaments of 50-60 players " \
       "per round count (3, 5, 6, 7) through the production pairing, rolled back; SEAT_REPORT_PER, " \
       "SEAT_REPORT_SEED=2026, SEAT_REPORT_WORKERS. Takes several minutes."
  task seat_report: :environment do
    abort "grindin:seat_report creates and rolls back tournaments; it never runs in production" if Rails.env.production?

    ActiveJob::Base.queue_adapter = :test
    ActionMailer::Base.perform_deliveries = false
    ActiveModel::SecurePassword.min_cost = true
    Rails.application.eager_load! # once, before the workers fork
    per = (ENV["SEAT_REPORT_PER"] || 500).to_i
    options = { per: per, seed: (ENV["SEAT_REPORT_SEED"] || 2026).to_i,
                workers: (ENV["SEAT_REPORT_WORKERS"] || [Etc.nprocessors, 8].min).to_i }
    report =
      [3, 5, 6, 7].index_with do |rounds|
        Grindin::SeatReport.summarize(rounds, Grindin::SeatReport.in_processes(rounds: rounds, **options))
      end
    path = Rails.root.join("config/seat_fairness.json")
    path.write(JSON.pretty_generate({ "generated_on" => Date.current.iso8601, "tournaments_per_rounds" => per,
                                      "players" => [50, 60], "rounds" => report }) + "\n")
    puts "wrote #{path}"
    report.each do |rounds, data|
      puts "#{rounds} rounds: fair spread<=1 #{data['fair'][:fair_rate]}% never1 #{data['fair'][:never_first]}% | " \
           "random #{data['random'][:fair_rate]}% never1 #{data['random'][:never_first]}%"
    end
  end
end
