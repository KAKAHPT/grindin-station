# frozen_string_literal: true

require "test_helper"

module Play
  class PairingsControllerTest < ActionDispatch::IntegrationTest # rubocop:disable Metrics/ClassLength
    setup do
      @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
      @tournament.update_columns(swiss_rounds_count: 3, top_cut_size: 0) # rubocop:disable Rails/SkipsModelValidations
      @round = @tournament.rounds.create!(type: SwissRound, number: 1)
      @round.update!(published: true)
    end

    test "a visitor sees the latest published round: tables, status and seats in order" do
      get play_pairings_path(@tournament.slug)

      assert_response :success
      assert_select "h2", text: "Pairings"
      @round.pods.preload(seatings: { event_participant: { player: :user } }).find_each do |pod|
        assert_select "[data-pod-number='#{pod.number}']" do
          assert_select "h3", text: /Table\s+#{pod.number}/
          assert_select "[data-pod-status]", text: /Playing/
          names = pod.seatings.map { |seating| seating.event_participant.name }
          assert_select "li[data-seat]" do |rows|
            assert_equal (1..names.size).map(&:to_s), rows.pluck("data-seat")
            assert_equal(names, rows.map { |row| row.at_css("[data-name]").text.strip })
          end
        end
      end
      assert_select "a[href*='/organizer']", count: 0
      assert_select "button", count: 0
    end

    test "the nav links the pairings and the new standings" do
      get play_pairings_path(@tournament.slug)

      assert_select "nav[data-play-nav] a[href=?][aria-current=page]", play_pairings_path(@tournament.slug),
                    text: "Pairings"
      assert_select "nav[data-play-nav] a[href=?]", play_standings_path(@tournament.slug), text: "Standings"
    end

    test "a completed table marks the winner and a drawn one shows Draw" do
      TournamentBuilder.play_round!(@tournament, winners: { 1 => 2, 2 => :draw })
      winner = @round.pods.find_by!(number: 1).seatings.find_by!(order: 3).event_participant

      get play_pairings_path(@tournament.slug)

      assert_select "[data-pod-number='1']" do
        assert_select "[data-pod-status]", text: /Completed/
        assert_select "li[data-winner]", count: 1
        assert_select "li[data-winner][data-participant-id=?]", winner.id
      end
      assert_select "[data-pod-number='2']" do
        assert_select "[data-draw]", text: "Draw"
        assert_select "li[data-winner]", count: 0
      end
    end

    test "?round=N shows an earlier closed round; an unpublished round is not found" do
      TournamentBuilder.play_round!(@tournament, winners: { 1 => 0, 2 => 0 })
      @tournament.rounds.create!(type: SwissRound, number: 2).update!(published: true)
      third = @tournament.rounds.create!(type: SwissRound, number: 3)

      get play_pairings_path(@tournament.slug)
      assert_select "[data-round-number='2']"

      get play_pairings_path(@tournament.slug, round: 1)
      assert_response :success
      assert_select "[data-round-number='1']"
      assert_select "[data-round-selector] a[href=?]", play_pairings_path(@tournament.slug, round: 2)

      get play_pairings_path(@tournament.slug, round: third.number)
      assert_response :not_found

      get play_pairings_path(@tournament.slug, round: 99)
      assert_response :not_found
    end

    test "before any round is published the page says so" do
      @round.update!(published: false)

      get play_pairings_path(@tournament.slug)

      assert_response :success
      assert_select "[data-pod-number]", count: 0
      assert_includes response.body, "Waiting for pairings"
    end

    test "commanders only when the event shows them" do
      @round.pods.first.seatings.first.event_participant.update!(decklist: "Kinnan, Bonder Prodigy")

      get play_pairings_path(@tournament.slug)
      assert_not_includes response.body, "Kinnan, Bonder Prodigy"

      @tournament.update!(show_commanders_in_standings: true)
      get play_pairings_path(@tournament.slug)
      assert_includes response.body, "Kinnan, Bonder Prodigy"
    end

    test "every player of a round with a 3-player pod appears exactly once" do
      tournament = TournamentBuilder.build(players: 7, organizer: event_organizers(:standard_organizer))
      round = tournament.rounds.create!(type: SwissRound, number: 1)
      round.update!(published: true)
      assert_equal [3, 4], round.pods.map { |pod| pod.seatings.size }.sort

      get play_pairings_path(tournament.slug)

      assert_each_once(round.seatings.pluck(:event_participant_id))
    end

    test "every player of a 5-player pod appears exactly once" do
      tournament = TournamentBuilder.build(players: 5, organizer: event_organizers(:standard_organizer))
      round = tournament.rounds.create!(type: SwissRound, number: 1)
      round.update!(published: true)

      get play_pairings_path(tournament.slug)

      assert_each_once(round.seatings.pluck(:event_participant_id))
    end

    test "byes are listed at the end and every player of the round appears exactly once" do
      tournament = TournamentBuilder.build(players: 32, organizer: event_organizers(:standard_organizer))
      tournament.update_columns(swiss_rounds_count: 1, top_cut_size: 13) # rubocop:disable Rails/SkipsModelValidations
      tournament.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_round!(tournament, winners: (1..8).index_with(0))
      cut = tournament.rounds.create!(type: SingleEliminationRound, number: 2)
      cut.update!(published: true)
      bye = cut.byes.sole.event_participant

      get play_pairings_path(tournament.slug)

      assert_response :success
      assert_select "[data-byes] li[data-participant-id=?]", bye.id, text: /Bye:\s*#{bye.name}/
      assert_each_once(cut.seatings.pluck(:event_participant_id) + [bye.id])
    end

    test "renders in portuguese" do
      get play_pairings_path(@tournament.slug, locale: "pt")

      assert_response :success
      assert_select "h2", text: "Emparelhamentos"
      assert_select "h3", text: /Mesa\s+1/
    end

    private

    def assert_each_once(expected_ids)
      shown = css_select("[data-participant-id]").pluck("data-participant-id")
      assert_equal expected_ids.sort, shown.sort
      assert_equal shown.uniq, shown
    end
  end
end
