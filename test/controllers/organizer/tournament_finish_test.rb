# frozen_string_literal: true

require "test_helper"

module Organizer
  # Closing the last round finishes the tournament; Reopen takes it back for a correction.
  class TournamentFinishTest < ActionDispatch::IntegrationTest # rubocop:disable Metrics/ClassLength
    setup do
      sign_in_as(users(:organizer_user))
      @t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
    end

    test "closing the final finishes the tournament, ranks the cut winner first and shows the trophy" do
      final = with_final
      winner = final.pods.sole.seatings.find_by!(order: 3).event_participant
      post organizer_tournament_round_pod_results_path(@t, final, final.pods.sole),
           params: { result: { type: "Win", event_participant_id: winner.id } }

      patch organizer_tournament_round_path(@t, final), params: { round: { action: :close } }

      assert_redirected_to organizer_tournament_round_path(@t, final)
      assert_equal I18n.t("rounds.tournament_finished"), flash[:notice]
      assert_predicate @t.reload, :finished?
      assert_equal 1, winner.reload.final_position
      assert_equal (1..4).to_a, @t.event_participants.pluck(:final_position).sort

      get play_standings_path(@t.slug)
      assert_response :success
      assert_select "tbody tr:first-child [data-winner]", count: 1
      assert_select "tbody tr:first-child", text: /#{Regexp.escape(winner.name)}/
    end

    test "closing the last swiss round finishes a tournament without a cut" do
      @t.update_columns(swiss_rounds_count: 1, top_cut_size: 0) # rubocop:disable Rails/SkipsModelValidations
      round = @t.rounds.create!(type: SwissRound, number: 1)
      round.update!(published: true, started_at: Time.current)
      winner = round.pods.sole.seatings.find_by!(order: 1).event_participant
      post organizer_tournament_round_pod_results_path(@t, round, round.pods.sole),
           params: { result: { type: "Win", event_participant_id: winner.id } }

      patch organizer_tournament_round_path(@t, round), params: { round: { action: :close } }

      assert_predicate @t.reload, :finished?
      assert_equal 1, winner.reload.final_position
    end

    test "the last swiss round of a tournament with a cut waits for the organizer to make it" do
      @t.update_columns(swiss_rounds_count: 1, top_cut_size: 4) # rubocop:disable Rails/SkipsModelValidations
      round = @t.rounds.create!(type: SwissRound, number: 1)
      round.update!(published: true, started_at: Time.current)
      winner = round.pods.sole.seatings.find_by!(order: 1).event_participant
      post organizer_tournament_round_pod_results_path(@t, round, round.pods.sole),
           params: { result: { type: "Win", event_participant_id: winner.id } }

      patch organizer_tournament_round_path(@t, round), params: { round: { action: :close } }

      assert_predicate @t.reload, :swiss?
      assert_equal I18n.t("rounds.closed"), flash[:notice]
    end

    test "the last swiss round offers Finish without cut, which finishes with the swiss order" do
      @t.update_columns(swiss_rounds_count: 1, top_cut_size: 4) # rubocop:disable Rails/SkipsModelValidations
      round = @t.rounds.create!(type: SwissRound, number: 1)
      round.update!(published: true, started_at: Time.current)
      winner = round.pods.sole.seatings.find_by!(order: 1).event_participant
      post organizer_tournament_round_pod_results_path(@t, round, round.pods.sole),
           params: { result: { type: "Win", event_participant_id: winner.id } }
      patch organizer_tournament_round_path(@t, round), params: { round: { action: :close } }

      get organizer_tournament_round_path(@t, round)
      assert_select "form[action=?] button", organizer_tournament_path(@t), text: /Finish without cut/

      patch organizer_tournament_path(@t), params: { tournament: { state: :finished } }

      assert_predicate @t.reload, :finished?
      assert_equal 1, winner.reload.final_position
    end

    test "/rounds without an id opens the latest round, or the Overview before the first one" do
      get organizer_tournament_rounds_path(@t)
      assert_redirected_to organizer_tournament_path(@t)

      final = with_final
      get organizer_tournament_rounds_path(@t)
      assert_redirected_to organizer_tournament_round_path(@t, final)
    end

    test "reopen takes a finished tournament back to its final, clears the positions, and closing again finishes" do
      final = finish_with_final
      assert_predicate @t.reload, :finished?

      patch reopen_organizer_tournament_path(@t)

      assert_redirected_to organizer_tournament_round_path(@t, final)
      assert_equal I18n.t("flash.notice.tournament_reopened"), flash[:notice]
      assert_predicate @t.reload, :single_elimination?
      assert_nil final.reload.finished_at
      assert_equal [nil] * 4, @t.event_participants.pluck(:final_position)
      reopened = AuditEvent.where(action: "event_state_changed", event: @t).where("data->>'to' = ?",
                                                                                  "single_elimination")
      assert_equal 1, reopened.count

      get organizer_tournament_path(@t)
      assert_select "form[action=?]", reopen_organizer_tournament_path(@t), count: 0

      patch organizer_tournament_round_path(@t, final), params: { round: { action: :close } }
      assert_predicate @t.reload, :finished?
      assert_equal (1..4).to_a, @t.event_participants.pluck(:final_position).sort
    end

    test "a finished tournament offers Reopen to the organizer only" do
      finish_with_final
      get organizer_tournament_path(@t)
      assert_select "form[action=?]", reopen_organizer_tournament_path(@t), count: 1

      judge = User.create!(name: "Judge", email_address: "judge-#{SecureRandom.hex(3)}@example.com",
                           password: "password123")
      EventStaff.create!(event: @t, user: judge, role: "judge")
      sign_in_as(judge)
      patch reopen_organizer_tournament_path(@t)
      assert_redirected_to organizer_root_url
      assert_predicate @t.reload, :finished?
    end

    private

    # One swiss round played, the cut made, the final published with no result yet.
    def with_final
      @t.update_columns(swiss_rounds_count: 1, top_cut_size: 4) # rubocop:disable Rails/SkipsModelValidations
      @t.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_round!(@t, winners: { 1 => 0 })
      @t.update_column(:state, :single_elimination) # rubocop:disable Rails/SkipsModelValidations
      final = @t.rounds.create!(type: SingleEliminationRound, number: 2)
      final.update!(published: true, started_at: Time.current)
      final
    end

    def finish_with_final
      final = with_final
      winner = final.pods.sole.seatings.find_by!(order: 2).event_participant
      post organizer_tournament_round_pod_results_path(@t, final, final.pods.sole),
           params: { result: { type: "Win", event_participant_id: winner.id } }
      patch organizer_tournament_round_path(@t, final), params: { round: { action: :close } }
      final
    end

    def sign_in_as(user)
      post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
    end
  end
end
