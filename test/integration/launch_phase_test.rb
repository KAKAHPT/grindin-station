# frozen_string_literal: true

require "test_helper"

# The site as production runs it (config/features.yml, `shared`): the cEDH tournament and, since 2026-11-26, the
# leagues are public. Every address of a paused module is not found, whoever asks; the tournament pages still
# open and link to nothing that is paused; players' names still open their profile. The rest of the suite runs
# with every module on.
class LaunchPhaseTest < ActionDispatch::IntegrationTest # rubocop:disable Metrics/ClassLength
  # Where the paused modules live. Kept apart from config/routes.rb on purpose: a route added to one of these
  # modules without its switch fails here.
  PAUSED = %r{\A/(feed|follows|rankings|circuits|organizers|o/|teams|team_memberships|
                  organizer/(circuits|about)|admin/(feed|circuits|invitational))(/|\z|\(|\.)}x
  PAUSED_WITHOUT_RANKINGS = %r{\A/(feed|follows|circuits|organizers|o/|teams|team_memberships)(/|\z|\?|\.)}
  VERBS = %w[GET POST PATCH PUT DELETE].freeze
  LINKS = "a[href], form[action], [formaction], turbo-frame[src], iframe[src]"
  LINK_ATTRIBUTES = %w[href action formaction src].freeze

  setup do
    Features.settings = Features.launch
    @owner = users(:organizer_user)
    @owner.update_columns(admin: true) # rubocop:disable Rails/SkipsModelValidations
    @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
    @tournament.update_columns(swiss_rounds_count: 2, top_cut_size: 0) # rubocop:disable Rails/SkipsModelValidations
    round = @tournament.rounds.create!(type: SwissRound, number: 1)
    round.update!(published: true, started_at: Time.current)
    @player = round.pods.first.seatings.first.event_participant.player.user
    @player.update!(password: "password123", handle: "launch-player", visibility: "public", team: "Tagged")
  end

  teardown { Features.settings = nil }

  test "only the cEDH tournament, the leagues and the seat report are on" do
    assert_equal Features::NAMES.index_with { |name| name.in?(%i[fairness leagues]) }, Features.launch
  end

  test "the seat report opens and the landing links to it" do
    get "/fairness"
    assert_response :success

    get "/"
    assert_select "a[data-tests][href=?]", "/fairness"
  end

  test "an unknown module name raises instead of reading as off" do
    assert_raises(KeyError) { Features.on?(:fed) }
  end

  test "every address of a paused module is not found, even for the organizer who is also the site admin" do
    routes = paused_routes
    assert_operator routes.size, :>=, 35

    [nil, @owner].each do |user|
      reset!
      sign_in(user) if user
      found = routes.reject { |route| process(route.verb.downcase.to_sym, path_for(route)) && response.not_found? }

      assert_empty found.map { |route| "#{route.verb} #{route.path.spec}" }, "answered for #{user&.name || 'a visitor'}"
    end
  end

  test "the tournament pages open and link to nothing that is paused" do
    slug = @tournament.slug
    visitor = ["/", "/events", "/tournaments", "/privacy", "/t/#{slug}", "/t/#{slug}/pairings",
               "/t/#{slug}/standings", "/p/launch-player", "/fairness"]

    assert_pages_without_paused_links(visitor)
    sign_in(@player)
    assert_pages_without_paused_links(visitor + ["/account", "/t/#{slug}/me", "/notifications"])
    reset!
    sign_in(@owner)
    assert_pages_without_paused_links(visitor + organizer_pages)
  end

  # The next module to come back: checked ahead, so switching it on is one line.
  test "with rankings switched on the page has no Teams tab, team or format filter, and links to nothing paused" do
    Rankings::Rebuild.call
    Features.settings = Features.launch.merge(rankings: true)

    %w[points elo teams].each do |tab|
      get "/rankings", params: { tab: tab, season: "all", team: "Tagged", play: "legacy" }

      assert_response :success
      assert_select "[data-rankings-tabs] a", count: 2
      assert_select "select[name=team], select[name=play], [data-team], [data-circuits-note]", count: 0
      targets = response.parsed_body.css(LINKS).flat_map { |node| LINK_ATTRIBUTES.filter_map { |name| node[name] } }
      assert_empty targets.grep(PAUSED_WITHOUT_RANKINGS), "/rankings?tab=#{tab} links to a paused module"
    end
    get "/"
    assert_select ".topbar-links a[href^='/rankings']"
  end

  test "names in the pairings and the standings open the player's profile" do
    %w[pairings standings].each do |page|
      get "/t/#{@tournament.slug}/#{page}"

      assert_select "a[href^='/p/launch-player']", { minimum: 1 }, "no profile link on #{page}"
    end
  end

  test "the profile shows the history without Follow, follower counts or the team" do
    get "/p/launch-player"

    assert_response :success
    assert_select "h1", text: @player.display_name
    assert_select "[data-profile-follow], [data-follow-counts], [data-team]", count: 0
  end

  test "the account page has no team card and no feed setting" do
    sign_in(@player)
    get "/account"

    assert_response :success
    assert_select "[data-team-card], #user_feed_scope", count: 0
  end

  test "the menu has Events only" do
    get "/"

    assert_select ".topbar-links a", count: 1
    assert_select ".topbar-links a[href^='/events']"
  end

  test "the landing keeps the waiting list and the fair-seats story, without circuits or format filter" do
    circuit = Circuit.create!(name: "Paused circuit", event_organizer: event_organizers(:standard_organizer))
    circuit.update_columns(featured: true) # rubocop:disable Rails/SkipsModelValidations
    get "/"

    assert_response :success
    assert_select "form[action='#{waitlist_signups_path}']"
    assert_select ".lp-why"
    assert_select "[data-featured-circuits], [data-upcoming-filter]", count: 0
    assert_select ".lp-lead", text: I18n.t("landing.lead_cedh")
  end

  test "a new tournament is always Commander / cEDH" do
    sign_in(@owner)
    get "/organizer/tournaments/new"

    assert_select "select[name='tournament[game_format]'] option", count: 1
    assert_select "select[name='tournament[game_format]'] option[value='commander']"

    post "/organizer/tournaments", params: {
      tournament: { name: "Forced 1v1", start_time: 1.day.from_now, end_time: 2.days.from_now, game_format: "modern",
                    format: "one_v_one" }
    }
    created = Tournament.find_by!(name: "Forced 1v1")

    assert_equal %w[multiplayer commander], [created.format, created.game_format]
  end

  test "the events list shows tournaments and leagues" do
    League.create!(name: "Open league", event_organizer: event_organizers(:standard_organizer),
                   start_time: 1.day.from_now, end_time: 2.days.from_now, state: :registration_open)
    get "/events"

    assert_response :success
    assert_match "Open league", response.body
  end

  private

  def sign_in(user)
    post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
    assert_response :redirect
  end

  def organizer_pages
    base = "/organizer/tournaments/#{@tournament.id}"
    ["/organizer", "/organizer/tournaments/new", base, "#{base}/edit", "#{base}/event_participants",
     "#{base}/rounds/#{@tournament.rounds.first.id}", "/admin", "/admin/events", "/admin/organizers", "/admin/audit"]
  end

  def assert_pages_without_paused_links(paths)
    paths.each do |path|
      get path
      assert_response :success, "#{path} answered #{response.status}"
      targets = response.parsed_body.css(LINKS).flat_map { |node| LINK_ATTRIBUTES.filter_map { |name| node[name] } }

      assert_empty targets.grep(PAUSED), "#{path} links to a paused module"
    end
  end

  def paused_routes
    Rails.application.routes.routes.select do |route|
      VERBS.include?(route.verb) && route.path.spec.to_s.match?(PAUSED)
    end
  end

  def path_for(route)
    route.path.spec.to_s.sub("(.:format)", "").gsub(/:(\w+)/) do
      ::Regexp.last_match(1) == "handle" ? "launch-player" : SecureRandom.uuid
    end
  end
end
