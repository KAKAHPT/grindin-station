# frozen_string_literal: true

require "test_helper"

module Organizer
  class TournamentsControllerTest < ActionDispatch::IntegrationTest # rubocop:disable Metrics/ClassLength
    setup do
      post session_path,
           params: { session: { email_address: users(:organizer_user).email_address, password: "password123" } }
    end

    test "the new form has no structure suggestion before anyone registers" do
      get new_organizer_tournament_path
      assert_response :success
      assert_not_includes response.body, "Suggested for"
    end

    test "an invalid tournament re-renders the form with 422 instead of redirecting" do
      assert_no_difference -> { Tournament.count } do
        post organizer_tournaments_path, params: {
          tournament: { name: "Inválido", start_time: 1.day.from_now, end_time: 2.days.from_now, round_minutes: 0 }
        }
      end
      assert_response :unprocessable_entity
      assert_select "form[action='#{organizer_tournaments_path}']"
    end

    test "a staff organizer can move the tournament to swiss, a judge cannot" do
      tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer),
                                           state: :registration_closed)
      co_organizer, judge =
        %w[organizer judge].map do |role|
          user = User.create!(name: role, email_address: "#{role}-#{SecureRandom.hex(3)}@example.com",
                              password: "password123")
          EventStaff.create!(event: tournament, user: user, role: role)
          user
        end

      sign_in(judge)
      patch organizer_tournament_path(tournament), params: { tournament: { state: "swiss" } }
      assert_redirected_to organizer_root_path
      assert tournament.reload.registration_closed?

      sign_in(co_organizer)
      get edit_organizer_tournament_path(tournament)
      assert_response :success
      patch organizer_tournament_path(tournament), params: { tournament: { state: "swiss" } }
      assert tournament.reload.swiss?
      assert_equal 1, tournament.rounds.count
    end

    test "the new form offers the format, and the match length for 1v1 behind the format-fields toggle" do
      get new_organizer_tournament_path

      assert_select "form[data-controller~=format-fields]" do
        assert_select "select[name='tournament[format]']:not([disabled])" do
          assert_select "option[value=multiplayer][selected]", text: "Multiplayer pods"
          assert_select "option[value=one_v_one]", text: "1v1"
        end
        assert_select "[data-format-fields-target=matchGames][hidden] select[name='tournament[match_games]']" do
          assert_select "option[value='3']", text: "Best of 3"
          assert_select "option[value='1']", text: "Best of 1"
        end
        assert_select "input[name='tournament[points_win]'][data-format-fields-target=points][value='7']"
      end
    end

    test "a 1v1 best-of-one tournament is created from the form" do
      assert_difference -> { Tournament.count } do
        post organizer_tournaments_path, params: {
          tournament: { name: "Duelos", start_time: 1.day.from_now, end_time: 2.days.from_now,
                        format: "one_v_one", match_games: "1",
                        points_win: 3, points_draw: 1, points_loss: 0, points_bye: 3 }
        }
      end

      tournament = Tournament.find_by!(name: "Duelos")
      assert_equal ["one_v_one", 1, 3], [tournament.format, tournament.match_games, tournament.points_win]
    end

    test "the edit form shows the format locked and keeps the match length visible for 1v1" do
      tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                           state: :registration_open, format: "one_v_one")

      get edit_organizer_tournament_path(tournament)

      assert_response :success
      assert_select "select[name='tournament[format]'][disabled] option[value=one_v_one][selected]"
      assert_select "[data-format-fields-target=matchGames]:not([hidden]) select[name='tournament[match_games]']"
    end

    test "Settings features the tournament on the landing and takes it off again" do
      tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                           state: :registration_open)

      get edit_organizer_tournament_path(tournament)
      assert_select "input[type=checkbox][name='tournament[featured]']:not([checked])"
      assert_select "label[for=tournament_featured]", text: "Feature on the landing"
      assert_select ".form-help", text: /Featured strip at the top of grindin.cedhpt.com/

      patch organizer_tournament_path(tournament), params: { tournament: { featured: "1" } }
      assert_redirected_to organizer_tournament_path(tournament)
      assert tournament.reload.featured?

      patch organizer_tournament_path(tournament), params: { tournament: { featured: "0" } }
      assert_not tournament.reload.featured?
    end

    test "a tampered update cannot switch the format" do
      tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                           state: :registration_open)

      patch organizer_tournament_path(tournament), params: { tournament: { format: "one_v_one", name: "Renomeado" } }

      assert_redirected_to organizer_tournament_path(tournament)
      assert_equal ["multiplayer", "Renomeado"], tournament.reload.values_at(:format, :name)
    end

    test "a mid-swiss update cannot switch the match length" do
      tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                           format: "one_v_one")

      patch organizer_tournament_path(tournament), params: { tournament: { match_games: "1" } }

      assert_response :unprocessable_entity
      assert_equal 3, tournament.reload.match_games
    end

    test "a mid-swiss update cannot step back to registration_closed nor reopen the points" do
      tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
      assert tournament.swiss?

      patch organizer_tournament_path(tournament),
            params: { tournament: { state: "registration_closed", points_win: "10" } }

      assert_response :unprocessable_entity
      tournament.reload
      assert tournament.swiss?
      assert_equal 7, tournament.points_win
    end

    test "the index shows the active tournaments as cards with state chips and the Active/Past switch" do
      active = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                       state: :registration_open)
      past = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer), state: :finished)

      get organizer_tournaments_path

      assert_response :success
      assert_select "[data-tournaments-filter] a.seg-on", text: "Active"
      assert_select "[data-tournaments-filter] a[href=?]", organizer_tournaments_path(past: 1), text: "Past"
      assert_select "a[href=?]", new_organizer_tournament_path, text: "New tournament"
      assert_select "##{ActionView::RecordIdentifier.dom_id(active, :card)}" do
        assert_select "[data-state-chip=registration_open]", text: /Registration open/
        assert_select "a[href=?]", edit_organizer_tournament_path(active), text: "Edit"
        assert_select "[aria-disabled=true]", text: "No rounds yet"
      end
      assert_select "##{ActionView::RecordIdentifier.dom_id(past, :card)}", 0
      assert_no_legacy_classes

      get organizer_tournaments_path(past: 1)
      assert_select "[data-tournaments-filter] a.seg-on", text: "Past"
      assert_select "##{ActionView::RecordIdentifier.dom_id(past, :card)} [data-state-chip=finished]"
      assert_select "##{ActionView::RecordIdentifier.dom_id(active, :card)}", 0
    end

    test "the tournament page is the Overview tab of the shell: header, six tabs, counters, format, lately" do
      tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                           state: :registration_open)
      JudgeCall.create!(event: tournament, reason: "rules")

      get organizer_tournament_path(tournament)

      assert_response :success
      assert_select "[data-event-header]" do
        assert_select ".evhead-eyebrow", text: /Tournament · Registration open · Multiplayer pods/
        assert_select "a[href=?][target=_blank]", play_event_path(tournament.slug), text: "View public page"
        assert_select "form input[name='tournament[state]'][value=registration_closed]"
        assert_select "input[name='tournament[state]'][value=canceled]", 0
      end
      assert_tabs active: "Overview", open_calls: 1
      assert_select "[data-overview-counters] .card", 4
      assert_select "[data-overview-format]", text: /Swiss rounds/
      assert_select "[data-overview-lately]", text: /Judge called/
      assert_no_legacy_classes
    end

    test "Roster, Rounds, Judge Center, Staff and Settings render inside the shell with their tab active" do
      tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
      round = tournament.rounds.create!(type: SwissRound, number: 1)
      JudgeCall.create!(event: tournament, reason: "rules")

      { organizer_tournament_event_participants_path(tournament, layout: "application") => "Roster",
        organizer_tournament_round_path(tournament, round) => "Rounds",
        organizer_tournament_judge_calls_path(tournament) => "Judge Center",
        organizer_tournament_staff_index_path(tournament) => "Staff",
        edit_organizer_tournament_path(tournament) => "Settings" }.each do |path, tab|
        get path

        assert_response :success, path
        assert_select "[data-event-header] .evhead-title", text: tournament.name
        assert_tabs active: tab, open_calls: 1
        assert_no_legacy_classes
      end
      assert_select "[data-tabs] a[href=?]", organizer_tournament_round_path(tournament, round), text: "Rounds"
    end

    test "Settings is a full page with the Event, Structure, Results and Danger zone sections" do
      tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                           state: :registration_open)

      get edit_organizer_tournament_path(tournament)

      assert_select "turbo-frame#modal form", 0
      assert_select "[data-settings] .form-section" do |sections|
        assert_equal(%w[Event Structure Results], sections.map { |section| section.text.strip })
      end
      assert_select "[data-danger-zone] button", text: "Cancel event"
      assert_select "[data-settings] .field input.field-input[name='tournament[name]']"
    end

    test "a scorekeeper sees only the tabs of their role" do
      tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
      user = User.create!(name: "Score", email_address: "score-#{SecureRandom.hex(3)}@example.com",
                          password: "password123")
      EventStaff.create!(event: tournament, user: user, role: "scorekeeper")
      sign_in(user)

      get organizer_tournament_path(tournament)

      assert_select "[data-tabs] .tab", 3
      assert_select "[data-event-header] input[name='tournament[state]']", 0
    end

    test "a judge sees Overview, Roster, Rounds and Judge Center, and no Staff or Settings" do
      tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
      user = User.create!(name: "Judge", email_address: "judge-#{SecureRandom.hex(3)}@example.com",
                          password: "password123")
      EventStaff.create!(event: tournament, user: user, role: "judge")
      sign_in(user)

      get organizer_tournament_path(tournament)

      assert_select "[data-tabs] .tab", 4
      assert_select "[data-tabs] .tab", text: /Overview|Roster|Rounds|Judge Center/, count: 4
      assert_select "[data-tabs] .tab", text: /Staff|Settings/, count: 0
    end

    test "a tournament with no rounds shows the Rounds tab disabled" do
      tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                           state: :registration_open)

      get organizer_tournament_path(tournament)

      assert_select "[data-tabs] span.tab-off[aria-disabled=true]", text: "Rounds"
      assert_select "[data-tabs] a.tab", text: "Rounds", count: 0
    end

    test "a finished tournament's Rounds tab links to the last round" do
      tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
      tournament.rounds.create!(type: SwissRound, number: 1)
      later = tournament.rounds.create!(type: SwissRound, number: 2)
      tournament.update_columns(state: Tournament.states[:finished]) # rubocop:disable Rails/SkipsModelValidations

      get organizer_tournament_path(tournament)

      assert_select "[data-tabs] a[href=?]", organizer_tournament_round_path(tournament, later), text: "Rounds"
    end

    test "registration_closed with no swiss rounds offers single elimination in the header" do
      tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer),
                                           state: :registration_closed, format: "one_v_one")
      tournament.update_columns(swiss_rounds_count: 0, top_cut_size: 4) # rubocop:disable Rails/SkipsModelValidations

      get organizer_tournament_path(tournament)

      assert_select "[data-event-header] form input[name='tournament[state]'][value=single_elimination]"
      assert_select "[data-event-header] input[name='tournament[state]'][value=swiss]", 0
    end

    private

    def assert_tabs(active:, open_calls:)
      assert_select "[data-tabs] .tab", 6
      assert_select "[data-tabs] .tab-on", 1
      assert_select "[data-tabs] .tab-on", text: /\A\s*#{active}/
      assert_select "[data-tabs] [data-judge-calls-count]", text: open_calls.to_s
    end

    def assert_no_legacy_classes
      assert_select "[class*=purple], [class*=orange-], [class*=bg-gray], [class*='dark:']", 0
    end

    def sign_in(user)
      post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
    end
  end
end
