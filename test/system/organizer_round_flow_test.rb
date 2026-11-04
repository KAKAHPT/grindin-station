# frozen_string_literal: true

require "application_system_test_case"

# Flow 1: the organizer takes a 16-player event from registration to a published first round.
class OrganizerRoundFlowTest < ApplicationSystemTestCase
  setup do
    @tournament = TournamentBuilder.build(players: 16, organizer: event_organizers(:standard_organizer),
                                          state: :registration_open)
    @tournament.update_columns(swiss_rounds_count: 2, top_cut_size: 4) # rubocop:disable Rails/SkipsModelValidations
  end

  test "organizer closes registrations, starts the swiss and publishes round 1" do
    sign_in_as(users(:organizer_user))
    visit organizer_tournament_path(@tournament)

    accept_confirm { click_button "Close Registrations" }
    assert_text I18n.t("flash.notice.tournament_updated")
    assert_predicate @tournament.reload, :registration_closed?

    accept_confirm { click_button "Move to Swiss stage" }
    assert_text I18n.t("flash.notice.tournament_updated")
    assert_predicate @tournament.reload, :swiss?

    click_link "Bracket"
    assert_text "Round #1"
    click_button "Publish"
    assert_text I18n.t("flash.notice.round_published")

    round = @tournament.rounds.find_by!(number: 1)
    assert_predicate round, :published?
    assert_equal 4, round.pods.count

    round.pods.preload(seatings: :event_participant).find_each do |pod|
      within "#pod_#{pod.id}" do
        assert_selector "h5", text: "Table #{pod.number}"
        pod.seatings.each do |seating|
          assert_selector "li", text: /\A#{seating.order}\s*#{Regexp.escape(seating.event_participant.name)}\b/
        end
      end
    end
    assert_button "Start"
  end
end
