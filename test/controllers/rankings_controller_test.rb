# frozen_string_literal: true

require "test_helper"
require_relative "../support/rankings_fixture"

class RankingsControllerTest < ActionDispatch::IntegrationTest # rubocop:disable Metrics/ClassLength
  include RankingsFixture

  setup { build_rankings_world }

  test "the points tab: tabs, summary strip, rows and the topbar link" do
    get rankings_path

    assert_response :success
    assert_select "h1", text: "Rankings"
    assert_select "[data-rankings-tabs] a", 3
    assert_select "[data-rankings-tabs] a.on[href=?]", rankings_path(tab: "points")
    assert_select "header a.on[href=?]", rankings_path
    assert_select "[data-filter-chips]", 0
    assert_select "[data-summary] [data-summary-players]", text: "4"
    assert_select "[data-summary] [data-summary-events]", text: "3"
    assert_select "[data-summary] [data-summary-organizers]", text: "2"
    assert_select "tr[data-player]", 4
    assert_select "tr[data-player]:first-child" do
      assert_select "a[href=?]", profile_path("ana"), text: "Ana Carvalho"
      assert_select "[data-team]", text: "Porto Grinders"
      assert_select "td.text-ink", text: "1"
      assert_select "[data-points]", text: "26"
      assert_select "[data-best]", text: "1st"
    end
    assert_select "tr[data-player]:nth-child(4) td.text-muted", text: "4"
    assert_select "a[href=?]", circuits_path
  end

  test "the filter bar: search, season links, selects that submit on change, the tab and the count" do
    get rankings_path
    assert_select "form[data-filter-bar][method=get][action=?]", rankings_path do
      assert_select "input[name=q]"
      assert_select "a.seg-on[href=?]", rankings_path(season: @this_year, tab: "points"), text: @this_year.to_s
      assert_select "a", text: "All time"
      assert_select "select[name=country][data-action='change->submit-on-change#submit'] option[value=ES]",
                    text: "Spain"
      assert_select "select[name=organizer] option[value=lisboa-cedh]", text: "Lisboa cEDH"
      assert_select "select[name=play] option", 8 # All formats + the seven plays
      assert_select "select[name=play] option[value='']", text: "All formats"
      assert_select "select[name=play] option[value=legacy]", text: "Legacy"
      assert_select "select[name=team] option", text: "Porto Grinders"
      assert_select "input[type=hidden][name=tab][value=points]"
      assert_select "[data-filter-count]", text: "4 players"
    end
  end

  test "active filters show as chips with a remove link and Clear all" do
    get rankings_path(country: "ES", organizer: "lisboa-cedh", q: "carl")

    assert_select "[data-filter-chips]" do
      assert_select "[data-chip]", 3
      assert_select "[data-chip] a[href=?]", rankings_path(organizer: "lisboa-cedh", q: "carl")
      assert_select "a[data-clear-all][href=?]", rankings_path(tab: "points")
    end
    assert_select "tr[data-player]", 1
    assert_select "select[name=country] option[selected][value=ES]"
  end

  test "20 rows then Show all, all=1 shows every row" do
    crowd = TournamentBuilder.build(players: 24, organizer: @standard, state: :finished)
    crowd.update_columns(start_time: Time.zone.local(@this_year, 7, 1)) # rubocop:disable Rails/SkipsModelValidations
    Rankings::Rebuild.call

    get rankings_path

    assert_select "tr[data-player]", 20
    assert_select "a[data-show-all][href=?]", rankings_path(all: 1), text: "Show all 28"

    get rankings_path(all: 1)

    assert_select "tr[data-player]", 28
    assert_select "a[data-show-all]", 0
  end

  test "segment links keep only the bar's params" do
    get rankings_path(country: "ES", page: 3, utm_source: "x", all: 1)

    assert_select "a[href=?]", rankings_path(country: "ES", tab: "points", season: "all"), text: "All time"
  end

  test "the current year with no data yet shows the empty state" do
    travel_to Time.zone.local(@this_year + 1, 2, 1) do
      get rankings_path

      assert_select "a.seg-on", text: (@this_year + 1).to_s
      assert_select "tr[data-player]", 0
      assert_select "td", text: "No players match."
    end
  end

  test "the leaderboard tab shows the rating columns and the provisional mark" do
    get rankings_path(tab: "elo")

    assert_response :success
    assert_select "th", text: "Rating"
    assert_select "th", text: "Peak"
    assert_select "tr[data-player]", 4
    assert_select "tr[data-player] [data-provisional]", 4
    assert_select "tr[data-player]:first-child [data-change].text-accent", text: /\A\+\d+\z/
    assert_select "[data-how=elo]"
  end

  test "the leaderboard defaults to the multiplayer pool, shown as a chip, with no All formats option" do
    get rankings_path(tab: "elo")

    assert_select "select[name=play] option", 7
    assert_select "select[name=play] option[value='']", 0
    assert_select "select[name=play] option[selected][value=multiplayer]"
    assert_select "[data-chip]", count: 1, text: %r{Format\s+Commander / cEDH}
    assert_select "[data-chip] a[href=?]", rankings_path(tab: "elo")
    assert_select "[data-summary-players]", text: "4"
  end

  test "?tab=elo&play=legacy lists the Legacy ratings; the chip's ✕ goes back to multiplayer" do
    get rankings_path(tab: "elo", play: "legacy")

    assert_select "tr[data-player]", 2
    assert_select "tr[data-player]:first-child", text: /Carla Costa/ do
      assert_select "[data-rating]", text: "1516"
    end
    assert_select "[data-chip]", text: /Format\s+Legacy/
    assert_select "[data-chip] a[href=?]", rankings_path(tab: "elo")
    assert_select "[data-summary-players]", text: "2"
    assert_select "[data-filter-count]", text: "2 players"
  end

  test "/rankings?play=modern narrows the points to Modern" do
    get rankings_path(play: "modern", season: "all")

    assert_select "tr[data-player]", 2
    assert_select "tr[data-player]:first-child", text: /Diogo Pereira/
    assert_select "[data-chip]", text: /Format\s+Modern/
  end

  test "the teams tab lists the teams" do
    get rankings_path(tab: "teams", season: "all")

    assert_response :success
    assert_select "tr[data-team-row]", 2
    assert_select "tr[data-team-row]:first-child", text: /Porto Grinders/ do
      assert_select "[data-points]", text: "129"
    end
    assert_select "[data-filter-count]", text: "2 teams"
  end

  test "a hidden profile shows the name without a link or handle" do
    @diogo.update!(visibility: "private")

    get rankings_path

    row = css_select("tr[data-player]").find { |tr| tr.text.include?("Diogo Pereira") }
    assert_empty row.css("a")
    assert_not_includes response.body, "@diogo"
  end

  test "a participants-only profile links for a player who shared an event" do
    @diogo.update!(visibility: "participants")
    sign_in(@ana)

    get rankings_path

    assert_select "a[href=?]", profile_path("diogo")
  end

  test "each tab has its note and dialog with the short and the detailed version" do
    %w[points elo teams].each do |tab|
      get rankings_path(tab: tab)

      assert_select "[data-controller=dialog] button[data-action='dialog#open']"
      assert_select "dialog[data-how=#{tab}]" do
        assert_select "[data-short]"
        assert_select "[data-detailed]"
        assert_select "button[data-action='dialog#close']"
      end
    end
  end

  test "renders in pt and es" do
    get rankings_path(locale: "pt")
    assert_select "h1", text: "Rankings"
    get rankings_path(locale: "es", tab: "elo")
    assert_response :success
  end

  test "each tab runs in at most 10 queries" do
    %w[points elo teams].each do |tab|
      count = count_queries { get rankings_path(tab: tab) }
      assert_response :success
      assert_operator count, :<=, 10, "#{tab} ran #{count} queries"
    end
  end

  test "a signed-in viewer on the leaderboard, with an avatar listed, runs in at most 12 queries" do
    @ana.avatar.attach(io: file_fixture("cover1.jpg").open, filename: "ana.jpg", content_type: "image/jpeg")
    sign_in(@bruno)

    count = count_queries { get rankings_path(tab: "elo") }

    assert_response :success
    assert_select "tr[data-player] img[src*='ana.jpg']"
    assert_operator count, :<=, 12, "signed-in elo ran #{count} queries"
  end

  private

  def sign_in(user)
    post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
  end

  # Cached hits count too: the query cache outlives a request in integration tests.
  def count_queries(&block)
    count = 0
    counter =
      lambda do |_name, _start, _finish, _id, payload|
        count += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION])
      end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end
