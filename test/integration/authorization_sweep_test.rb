# frozen_string_literal: true

require "test_helper"

# Every organizer and admin route, with every verb, requested by people who must not get in: a visitor, a
# player of the event and another organizer. Each must be turned away (sign-in, "not allowed" or 404) and
# nothing in the database may change. New routes are swept automatically, so a forgotten authorization
# rule fails here. Visitors are also turned away from every other route that changes data, a signed-in
# stranger cannot touch another player's records, and no route may answer with a server error.
class AuthorizationSweepTest < ActionDispatch::IntegrationTest # rubocop:disable Metrics/ClassLength
  # Routes a visitor may post to: signing in and up, password reset, e-mail confirmation, CSP reports, the
  # language switch and the landing page's waiting list.
  PUBLIC_WRITES = %w[sessions registrations passwords confirmations csp_reports omniauth_callbacks locales
                     waitlist].freeze
  WATCHED = [Event, Round, Pod, Seating, Result, EventParticipant, Infraction, JudgeCall, EventStaff, Circuit,
             Post, User, EventOrganizer, SiteSetting].freeze
  VERBS = %w[GET POST PATCH PUT DELETE].freeze

  setup do
    @owner = users(:organizer_user)
    @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
    @tournament.update_columns(swiss_rounds_count: 2, top_cut_size: 0) # rubocop:disable Rails/SkipsModelValidations
    @round = @tournament.rounds.create!(type: SwissRound, number: 1)
    @round.update!(published: true, started_at: Time.current)
    @pod = @round.pods.order(:number).first
    @participant = @pod.seatings.first.event_participant
    @result = Win.create!(round: @round, event_participant: @participant)
    @circuit = Circuit.create!(name: "Sweep circuit", event_organizer: event_organizers(:standard_organizer))
    @player = @participant.player.user.tap { |user| user.update!(password: "password123") }
    @rival = new_user("Rival Organizer")
    EventOrganizer.create!(user: @rival)
  end

  test "the owner reaches the swept pages, so the paths are real" do
    sign_in(@owner)
    pages = guarded_routes.select { |route| route.verb == "GET" }
    reached = pages.count { |route| get(path_for(route)) && response.successful? }

    assert_operator reached, :>=, 30, "only #{reached} organizer pages opened for the owner"
  end

  test "a visitor is sent to sign in on organizer routes and gets 404 on admin routes" do
    assert_turned_away(guarded_routes) do |route|
      response.not_found? || (!admin?(route) && response.redirect? && response.location == new_session_url)
    end
  end

  test "a player of the event is turned away from every organizer and admin route" do
    sign_in(@player)

    assert_turned_away(guarded_routes) do |route|
      response.not_found? || (!admin?(route) && not_allowed?)
    end
  end

  test "another organizer is turned away from every route of an event that is not theirs" do
    sign_in(@rival.reload)
    routes = guarded_routes.reject { |route| own_space?(route) }

    assert_operator routes.size, :>=, 100
    assert_turned_away(routes) do |route|
      response.not_found? || (!admin?(route) && response.redirect? && flash[:alert].present?)
    end
  end

  test "another organizer cannot put a tournament in a circuit that is not theirs" do
    sign_in(@rival.reload)

    post organizer_tournaments_path, params: {
      tournament: { name: "Hijack", start_time: 1.day.from_now, end_time: 2.days.from_now, game_format: "commander",
                    circuit_id: @circuit.id }
    }

    assert_empty @circuit.reload.tournaments
    assert_not Tournament.exists?(name: "Hijack", circuit_id: @circuit.id)
  end

  test "a visitor cannot change data through any other route" do
    routes = all_routes.reject { |route| route.verb == "GET" || guarded?(route) || public_write?(route) }

    assert_operator routes.size, :>=, 20
    assert_turned_away(routes) do |_route|
      response.not_found? || (response.redirect? && response.location == new_session_url)
    end
  end

  test "a signed-in stranger cannot change another player's post, team, sign-in method, registration or table" do
    records = victim_records
    sign_in(new_user("Stranger"))
    before = records.map { |record| record.reload.attributes }
    counts = -> { [Post, TeamMembership, Identity, EventParticipant, Result.unscoped, JudgeCall].map(&:count) }
    counted = counts.call

    statuses = stranger_requests(*records.first(3)).map { |verb, path, params| status_of(verb, path, params) }

    assert_equal(before, records.map { |record| record.reload.attributes })
    assert_equal counted, counts.call
    assert_empty(statuses.select { |status| status == 200 || status >= 500 })
  end

  # A second click, a page left open, a form sent empty: whoever asks, no route may answer with a server error.
  test "no route crashes when the owner, a player or a stranger sends it nothing" do
    crashes = [new_user("Stranger"), @player, @owner].flat_map { |user| crashes_for(user) }

    assert_empty crashes, "#{crashes.size} requests ended in a server error"
  end

  private

  def new_user(name)
    User.create!(name: name, email_address: "#{name.parameterize}-#{SecureRandom.hex(3)}@example.com",
                 password: "password123")
  end

  def sign_in(user)
    post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
    assert_response :redirect
  end

  def assert_turned_away(routes, &refused)
    before = fingerprint
    let_in = routes.reject { |route| refused?(route, &refused) }.map { |route| "#{route.verb} #{path_for(route)}" }

    assert_empty let_in, "#{let_in.size} of #{routes.size} routes were not refused"
    assert_equal before, fingerprint, "a refused request changed the database"
  end

  def refused?(route)
    process(route.verb.downcase.to_sym, path_for(route))
    yield(route)
  end

  # @player's post, team membership, sign-in identity and registration.
  def victim_records
    post_record = Post.new(user: @player, event: @tournament, body: "Mine", kind: "report")
    post_record.save!(validate: false) # a report needs a finished event; the owner check is what matters here
    team = Team.create!(name: "Victims", owner: @player)
    [post_record, TeamMembership.create!(team: team, user: @player, status: "accepted"),
     Identity.create!(user: @player, provider: "discord", uid: "victim-1"), @participant]
  end

  # What the stranger tries on records that belong to @player.
  def stranger_requests(post_record, membership, identity) # rubocop:disable Metrics/MethodLength -- one list
    participant_path = "/tournaments/#{@tournament.id}/event_participants/#{@participant.id}"
    pod_path = "/t/#{@tournament.slug}/pods/#{@pod.id}"
    [[:delete, "/feed/posts/#{post_record.id}", {}],
     [:patch, "/team_memberships/#{membership.id}", { status: "declined" }],
     [:delete, "/team_memberships/#{membership.id}", {}],
     [:delete, "/account/identities/#{identity.id}", {}],
     [:patch, participant_path, { event_participant: { decklist: "https://example.com/stolen" } }],
     [:delete, participant_path, {}],
     [:post, "#{pod_path}/report", { type: "Win", winner_id: @participant.id }],
     [:post, "#{pod_path}/confirm", {}],
     [:post, "#{pod_path}/contest", { reason: "not my table" }],
     [:post, "/t/#{@tournament.slug}/judge_calls", { reason: "not my event" }]]
  end

  def status_of(verb, path, params)
    process(verb, path, params: params)
    response.status
  end

  # Every route, reads first and deletes last, as this user.
  def crashes_for(user)
    reset!
    sign_in(user)
    all_routes.reject { |route| route.defaults[:controller].to_s.include?("omniauth") }
      .sort_by { |route| VERBS.index(route.verb) || VERBS.size }
      .filter_map { |route| crash(route, user) }
  end

  # "VERB path (who): error" when the request raises or answers 5xx, else nil.
  def crash(route, user)
    path = path_for(route)
    process(route.verb.downcase.to_sym, path)
    "#{route.verb} #{path} (#{user.name}): #{response.status}" if response.server_error?
  rescue StandardError => e
    "#{route.verb} #{path} (#{user.name}): #{e.class} #{e.message.first(120)}"
  end

  def not_allowed?
    response.redirect? && flash[:alert] == I18n.t("flash.alert.not_allowed")
  end

  def fingerprint
    WATCHED.map { |model| [model.name, model.unscoped.count, model.unscoped.maximum(:updated_at)] } +
      [@tournament.reload.attributes.except("updated_at")]
  end

  def all_routes
    Rails.application.routes.routes.select do |route|
      route.verb.present? && route.defaults[:controller].present? &&
        !route.path.spec.to_s.start_with?("/rails", "/assets", "/cable")
    end
  end

  def guarded_routes = all_routes.select { |route| guarded?(route) }
  def guarded?(route) = route.path.spec.to_s.start_with?("/organizer/", "/organizer(", "/admin")
  def admin?(route) = route.path.spec.to_s.start_with?("/admin")
  def public_write?(route) = PUBLIC_WRITES.any? { |name| route.defaults[:controller].to_s.include?(name) }

  # Pages every organizer has for their own data (lists, "new" forms, their about page): not another's event.
  # /organizer/circuits/:circuit_id/tournaments is the plain "new tournament" form (the circuit is ignored and
  # Event validates the circuit's owner), so it counts as the organizer's own space too.
  def own_space?(route)
    return false if admin?(route)

    parts = route.required_parts - [:format]
    parts.empty? || (parts == [:circuit_id] && route.defaults[:controller] == "organizer/tournaments")
  end

  def path_for(route)
    controller = route.defaults[:controller]
    route.path.spec.to_s.sub("(.:format)", "").gsub(/:(\w+)/) { segment(controller, ::Regexp.last_match(1)) }
  end

  def segment(controller, name)
    return record_id(controller) if name == "id"

    { "tournament_id" => @tournament.id, "round_id" => @round.id, "pod_id" => @pod.id,
      "event_participant_id" => @participant.id, "circuit_id" => @circuit.id, "handle" => @owner.handle,
      "slug" => @tournament.slug }.fetch(name) { SecureRandom.uuid }
  end

  def record_id(controller)
    owner_organizer = event_organizers(:standard_organizer)
    { "organizer/tournaments" => @tournament, "organizer/exports" => @tournament,
      "organizer/previews" => @tournament, "organizer/rounds" => @round, "organizer/pods" => @pod,
      "organizer/results" => @result, "organizer/event_participants" => @participant,
      "organizer/circuits" => @circuit, "admin/events" => @tournament, "admin/circuits" => @circuit,
      "admin/organizers" => owner_organizer, "tournaments" => @tournament, "circuits" => @circuit,
      "event_participants" => @participant, "rounds" => @round }.fetch(controller, nil)&.id || SecureRandom.uuid
  end
end
