# frozen_string_literal: true

require "test_helper"

module Organizer
  class RoundCloseTest < ActionDispatch::IntegrationTest # rubocop:disable Metrics/ClassLength
    setup do
      sign_in_as(users(:organizer_user))
      @t = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
      @t.update_columns(swiss_rounds_count: 2, top_cut_size: 4) # rubocop:disable Rails/SkipsModelValidations
      @round = start_round(1)
      @pod1, @pod2 = @round.pods.order(:number).to_a
    end

    test "close is refused while a table has no result, naming the table" do
      complete!(@pod1)

      patch organizer_tournament_round_path(@t, @round), params: { round: { action: "close" } }

      assert_response :unprocessable_content
      assert_nil @round.reload.finished_at
      assert_includes response.body, I18n.t("rounds.cannot_close", tables: @pod2.number.to_s)
    end

    test "close is refused while a table has an open judge call" do
      complete!(@pod1)
      complete!(@pod2)
      JudgeCalls::Open.call(event: @t, pod: @pod2, reason: "Rules question")

      patch organizer_tournament_round_path(@t, @round), params: { round: { action: "close" } }

      assert_response :unprocessable_content
      assert_nil @round.reload.finished_at
    end

    test "the old finish action no longer closes a round, here or on the public round page" do
      patch organizer_tournament_round_path(@t, @round), params: { round: { action: "finish" } }
      assert_response :unprocessable_content

      patch tournament_round_path(@t, @round), params: { round: { action: "finish" } }
      assert_response :not_found

      assert_nil @round.reload.finished_at
    end

    test "close with every table completed creates the next round unpublished" do
      complete!(@pod1)
      complete!(@pod2)

      patch organizer_tournament_round_path(@t, @round), params: { round: { action: "close" } }

      assert_not_nil @round.reload.finished_at
      next_round = @t.rounds.find_by!(number: 2)
      assert_not next_round.published?
      assert_redirected_to organizer_tournament_round_path(@t, next_round)
      follow_redirect!
      assert_includes response.body, I18n.t("rounds.next_round_created")
    end

    test "a staff result on a disputed table clears the dispute and closes its judge call" do
      @pod1.update!(disputed: true, pending_result: { "type" => "Draw" })
      call = JudgeCalls::Open.call(event: @t, pod: @pod1, reason: "Conflicting result reports")
      winner = @pod1.event_participants.first

      post organizer_tournament_round_pod_results_path(@t, @round, @pod1),
           params: { result: { type: "Win", event_participant_id: winner.id } }

      @pod1.reload
      assert_equal :completed, @pod1.report_status
      assert_not @pod1.disputed?
      assert_nil @pod1.pending_result
      assert call.reload.closed?
    end

    test "the pod card shows its state and one-click result buttons" do
      reporter = @pod1.seatings.first.event_participant_id
      @pod1.update!(pending_result: { "type" => "Draw" }, reported_by_participant_id: reporter,
                    reported_at: Time.current, confirmations: { reporter => Time.current.iso8601 })
      @pod2.update!(disputed: true)

      get organizer_tournament_round_path(@t, @round)

      assert_response :success
      assert_includes response.body, I18n.t("rounds.reported_by", seat: 1, time: @pod1.reported_at.strftime("%H:%M"))
      assert_includes response.body, I18n.t("rounds.confirmed", seats: "1")
      assert_includes response.body, I18n.t("rounds.disputed")
      assert_select "form[action='#{organizer_tournament_round_pod_results_path(@t, @round, @pod1)}'] " \
                    "input[name='result[type]'][value=Draw]"
    end

    test "make cut shows only on the last swiss round once closed, when there is a cut" do
      get organizer_tournament_round_path(@t, @round)
      assert_not_includes response.body, I18n.t("rounds.make_cut")

      TournamentBuilder.play_round!(@t, winners: { 1 => 0, 2 => 0 })
      last = start_round(2)
      get organizer_tournament_round_path(@t, last)
      assert_not_includes response.body, I18n.t("rounds.make_cut")

      last.pods.each { |pod| complete!(pod) }
      patch organizer_tournament_round_path(@t, last), params: { round: { action: "close" } }
      assert_redirected_to organizer_tournament_round_path(@t, last)
      follow_redirect!
      assert_includes response.body, I18n.t("rounds.make_cut")

      @t.update_columns(top_cut_size: 0) # rubocop:disable Rails/SkipsModelValidations
      get organizer_tournament_round_path(@t, last)
      assert_not_includes response.body, I18n.t("rounds.make_cut")
    end

    test "extra time adds five minutes per click, for every working role" do
      patch extra_time_organizer_tournament_round_pod_path(@t, @round, @pod1)
      assert_equal 5, @pod1.reload.extra_time

      judge = staff_user("judge")
      sign_in_as(judge)
      patch extra_time_organizer_tournament_round_pod_path(@t, @round, @pod1)
      assert_equal 10, @pod1.reload.extra_time

      sign_in_as(staff_user("scorekeeper"))
      patch extra_time_organizer_tournament_round_pod_path(@t, @round, @pod1)
      assert_equal 15, @pod1.reload.extra_time
    end

    test "a scorekeeper can still enter a result" do
      sign_in_as(staff_user("scorekeeper"))
      post organizer_tournament_round_pod_results_path(@t, @round, @pod1), params: { result: { type: "Draw" } }

      assert_equal :completed, @pod1.reload.report_status
    end

    private

    def start_round(number)
      round = @t.rounds.find_by(number: number) || @t.rounds.create!(type: SwissRound, number: number)
      round.update_columns(published: true, started_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      round
    end

    def complete!(pod)
      pod.seatings.each_with_index do |seating, i|
        (i.zero? ? Win : Loss).create!(round: pod.round, event_participant_id: seating.event_participant_id)
      end
    end

    def staff_user(role)
      user = User.create!(name: role.capitalize, email_address: "#{role}-#{SecureRandom.hex(3)}@example.com",
                          password: "password123")
      EventStaff.create!(event: @t, user: user, role: role)
      user
    end

    def sign_in_as(user)
      delete session_path
      post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
    end
  end
end
