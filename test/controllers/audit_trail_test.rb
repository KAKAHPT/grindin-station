# frozen_string_literal: true

require "test_helper"

# One request per audited action (spec M9 §2), asserting the row it writes: action, actor, event, data.
class AuditTrailTest < ActionDispatch::IntegrationTest # rubocop:disable Metrics/ClassLength
  setup do
    @player = users(:player_one)
    @organizer = users(:organizer_user)
  end

  # Sign-in and accounts

  test "sign_in, with the request ip" do
    row = audited("sign_in", actor: @player) { sign_in(@player, ip: "10.9.8.7") }
    assert_equal "10.9.8.7", row.ip
    assert_predicate row.request_id, :present?
  end

  test "sign_in_failed keeps only the e-mail as entered, never the password" do
    row =
      audited("sign_in_failed", actor: nil, data: { "email" => "player1@example.com" }) do
        post session_path, params: { session: { email_address: " Player1@Example.com ", password: "wrong-pass" } }
      end
    assert_equal ["email"], row.data.keys
  end

  test "sign_out" do
    sign_in(@player)
    audited("sign_out", actor: @player) { delete session_path }
  end

  test "sign_up" do
    audited("sign_up", actor: -> { User.find_by!(email_address: "new@example.com") }) do
      post registrations_path, params: { user: { name: "New", email_address: "new@example.com",
                                                 password: "password123", password_confirmation: "password123" } }
    end
  end

  test "oauth_sign_in with the provider" do
    @player.identities.create!(provider: "google_oauth2", uid: "g-1")
    mock_google(uid: "g-1", email: @player.email_address)

    audited("oauth_sign_in", actor: @player, data: { "provider" => "google_oauth2" }) do
      post "/auth/google_oauth2"
      follow_redirect!
    end
  end

  test "oauth_failed from the provider and from a refusal, with provider and reason" do
    audited("oauth_failed", actor: nil, data: { "provider" => "google_oauth2", "reason" => "invalid_credentials" }) do
      get "/auth/failure", params: { message: "invalid_credentials", strategy: "google_oauth2" }
    end

    mock_google(uid: "g-2", email: @player.email_address)
    audited("oauth_failed", actor: nil, data: { "provider" => "google_oauth2", "reason" => "email_taken" }) do
      post "/auth/google_oauth2"
      follow_redirect!
    end
  end

  test "password_reset_requested with the e-mail" do
    audited("password_reset_requested", actor: nil, data: { "email" => "player1@example.com" }) do
      post passwords_path, params: { email_address: "player1@example.com" }
    end
  end

  test "password_reset, never with the password or the token" do
    token = @player.password_reset_token
    row =
      audited("password_reset", actor: @player) do
        put password_path(token), params: { password: "new-pass-123", password_confirmation: "new-pass-123" }
      end
    assert_not_includes row.data.to_json, "new-pass-123"
    assert_not_includes row.data.to_json, token
  end

  test "password_changed, never with the password" do
    sign_in(@player)
    row =
      audited("password_changed", actor: @player) do
        patch account_path, params: { user: { password: "newpassword1", password_confirmation: "newpassword1",
                                              current_password: "password123" } }
      end
    assert_empty row.data
    assert_no_audit("email_changed")
  end

  test "email_changed from and to" do
    sign_in(@player)
    audited("email_changed", actor: @player,
                             data: { "from" => "player1@example.com", "to" => "renamed@example.com" }) do
      patch account_path, params: { user: { email_address: "renamed@example.com", current_password: "password123" } }
    end
    assert_no_audit("password_changed")
  end

  test "a profile change audits nothing" do
    sign_in(@player)
    assert_no_difference -> { AuditEvent.count } do
      patch account_path, params: { user: { bio: "Hello" } }
    end
  end

  test "account_deleted" do
    sign_in(@player)
    audited("account_deleted", actor: @player) { delete account_path, params: { confirmation: "delete" } }
  end

  test "identity_linked from the account page" do
    sign_in(@player)
    mock_google(uid: "g-3", email: "other@example.com")

    audited("identity_linked", actor: @player, data: { "provider" => "google_oauth2" }) do
      post "/auth/google_oauth2"
      follow_redirect!
    end
  end

  test "identity_unlinked" do
    sign_in(@player)
    identity = @player.identities.create!(provider: "discord", uid: "d-1")

    audited("identity_unlinked", actor: @player, data: { "provider" => "discord" }) do
      delete unlink_identity_path(identity)
    end
  end

  # Organizer actions

  test "staff_added and staff_removed with user, role and event" do
    sign_in(@organizer)
    tournament = build_tournament(state: :registration_open)
    data = { "user_id" => @player.id, "role" => "judge" }

    audited("staff_added", actor: @organizer, event: tournament, data: data) do
      post organizer_tournament_staff_index_path(tournament),
           params: { event_staff: { email_address: @player.email_address, role: "judge" } }
    end
    audited("staff_removed", actor: @organizer, event: tournament, data: data) do
      delete organizer_tournament_staff_path(tournament, tournament.event_staff.sole)
    end
  end

  test "result_corrected on a closed round, by the staff user" do
    sign_in(@organizer)
    tournament = build_tournament
    round = tournament.rounds.create!(type: SwissRound, number: 1)
    pod = round.pods.first
    winner = pod.seatings.last.event_participant
    TournamentBuilder.play_round!(tournament, winners: { 1 => 0 })

    data = { "pod_id" => pod.id, "round_number" => 1, "result" => "Win: #{winner.name}" }
    audited("result_corrected", actor: @organizer, event: tournament, data: data) do
      post organizer_tournament_round_pod_results_path(tournament, round, pod),
           params: { result: { type: "Win", event_participant_id: winner.id }, confirm: "1" }
    end
  end

  test "a result on an open round is not a correction" do
    tournament = build_tournament
    pod = tournament.rounds.create!(type: SwissRound, number: 1).pods.first

    assert_no_difference -> { AuditEvent.count } do
      Results::Apply.call(pod: pod, type: "Draw", by: @organizer)
    end
  end

  test "round_undone with the round number" do
    sign_in(@organizer)
    tournament = build_tournament
    tournament.rounds.create!(type: SwissRound, number: 1)
    TournamentBuilder.play_round!(tournament, winners: { 1 => 0 })
    round2 = tournament.rounds.create!(type: SwissRound, number: 2)

    audited("round_undone", actor: @organizer, event: tournament, data: { "round_number" => 2 }) do
      delete organizer_tournament_round_path(tournament, round2)
    end
  end

  test "round_closed with the round number" do
    sign_in(@organizer)
    tournament = build_tournament
    round = tournament.rounds.create!(type: SwissRound, number: 1)
    round.update_columns(published: true, started_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    round.pods.each do |pod|
      pod.seatings.each_with_index do |seating, i|
        (i.zero? ? Win : Loss).create!(round: round, event_participant_id: seating.event_participant_id)
      end
    end

    audited("round_closed", actor: @organizer, event: tournament, data: { "round_number" => 1 }) do
      patch organizer_tournament_round_path(tournament, round), params: { round: { action: "close" } }
    end
  end

  test "participant_dropped with the participant and reason" do
    sign_in(@organizer)
    tournament = build_tournament(state: :registration_closed)
    participant = tournament.event_participants.first

    audited("participant_dropped", actor: @organizer, event: tournament,
                                   data: { "participant_id" => participant.id, "reason" => "no_show" }) do
      patch drop_organizer_tournament_event_participant_path(tournament, participant), params: { reason: "no_show" }
    end
  end

  test "event_state_changed for a tournament" do
    sign_in(@organizer)
    tournament = build_tournament(state: :registration_open)

    audited("event_state_changed", actor: @organizer, event: tournament,
                                   data: { "from" => "registration_open", "to" => "registration_closed" }) do
      patch organizer_tournament_path(tournament), params: { tournament: { state: "registration_closed" } }
    end
  end

  test "event_state_changed for a league" do
    sign_in(@organizer)
    league = leagues(:standard_league)

    audited("event_state_changed", actor: @organizer, event: league,
                                   data: { "from" => "registration_open", "to" => "registration_closed" }) do
      patch organizer_league_path(league), params: { league: { state: "registration_closed" } }
    end
  end

  test "featured_changed from the organizer switch" do
    sign_in(@organizer)
    tournament = build_tournament(state: :registration_open)

    audited("featured_changed", actor: @organizer, event: tournament, data: { "featured" => true }) do
      patch organizer_tournament_path(tournament), params: { tournament: { featured: "1" } }
    end
    assert_no_audit("event_state_changed")
  end

  test "infraction_added and infraction_removed with penalty and participant" do
    sign_in(@organizer)
    tournament = build_tournament
    tournament.rounds.create!(type: SwissRound, number: 1)
    participant = tournament.event_participants.first
    data = { "penalty" => "warning", "participant_id" => participant.id }

    audited("infraction_added", actor: @organizer, event: tournament, data: data) do
      post organizer_tournament_infractions_path(tournament), params: {
        infraction: { player_id: participant.player_id, kind: "game_play_errors", category: "missed_trigger",
                      penalty: "warning", description: "Missed a trigger" }
      }
    end
    audited("infraction_removed", actor: @organizer, event: tournament, data: data) do
      delete organizer_tournament_event_participant_infraction_path(tournament, participant, Infraction.last)
    end
  end

  private

  # Runs the block, asserts it wrote exactly one row of this action and checks it; returns the row.
  def audited(action, actor:, event: nil, data: nil, &block)
    assert_difference(-> { AuditEvent.where(action: action).count }, 1, &block)
    row = AuditEvent.where(action: action).recent.first
    expected_actor = actor.respond_to?(:call) ? actor.call : actor
    assert_same_id expected_actor, row.actor_user_id, "#{action} actor"
    assert_same_id event, row.event_id, "#{action} event"
    assert_equal data, row.data, "#{action} data" if data
    row
  end

  def assert_same_id(record, id, message)
    record ? assert_equal(record.id, id, message) : assert_nil(id, message)
  end

  def assert_no_audit(action)
    assert_not AuditEvent.exists?(action: action), "#{action} was written"
  end

  def sign_in(user, ip: "127.0.0.1")
    post session_path, params: { session: { email_address: user.email_address, password: "password123" } },
                       env: { "REMOTE_ADDR" => ip }
  end

  def build_tournament(state: :swiss)
    TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer), state: state)
  end

  def mock_google(uid:, email:)
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: uid, info: { email: email, name: "Google Person" },
      extra: { raw_info: { email: email, email_verified: true } }
    )
  end
end
