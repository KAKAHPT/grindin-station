# frozen_string_literal: true

require "json"
require "shellwords"
require "tmpdir"

namespace :grindin do # rubocop:disable Metrics/BlockLength -- one task, kept in one place
  desc "Lighthouse (mobile, headless Chrome) on a URL, default the four demo-open pages; fail below 90"
  task :lighthouse, [:url] => :environment do |_, args| # rubocop:disable Metrics/BlockLength -- run + report + gate
    minimum = 90
    gated = %w[performance accessibility]
    base = ENV.fetch("LIGHTHOUSE_BASE", "http://localhost:3000")
    handle = User.find_by(email_address: "demo-p0@grindin.test")&.handle || "player-1"
    urls = %W[#{base}/t/demo-open #{base}/t/demo-open/standings #{base}/t/demo-open/pairings #{base}/p/#{handle}]
    urls = [args[:url]] if args[:url]
    chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    env = File.exist?(chrome) ? { "CHROME_PATH" => chrome } : {}

    failures =
      Dir.mktmpdir("lighthouse") do |dir|
        urls.each_with_index.flat_map do |url, index|
          report = File.join(dir, "report-#{index}.json")
          command = %W[npx --yes lighthouse@latest --preset=perf --form-factor=mobile --screenEmulation.mobile
                       --only-categories=performance,accessibility,best-practices --output=json
                       --output-path=#{report} --chrome-flags=--headless=new --quiet #{url}]
          system(env, *command) || abort("lighthouse failed on #{url}: #{command.shelljoin}")

          result = JSON.parse(File.read(report))
          scores = result["categories"].transform_values { |c| (c["score"] * 100).round }
          puts format("%<url>-50s performance %<p>3d  accessibility %<a>3d  best-practices %<b>3d",
                      url: url, p: scores["performance"], a: scores["accessibility"], b: scores["best-practices"])
          result["audits"].each_value do |audit| # what is left to fix: every audit that did not pass
            next unless audit["score"] && audit["score"] < 0.9 && audit["scoreDisplayMode"] != "informative"

            puts "  - #{audit['title']}#{" (#{audit['displayValue']})" if audit['displayValue'].present?}"
          end
          gated.select { |category| scores[category] < minimum }.map { |name| "#{url} #{name} #{scores[name]}" }
        end
      end

    abort("Below #{minimum}: #{failures.join(', ')}") if failures.any?
  end
end
