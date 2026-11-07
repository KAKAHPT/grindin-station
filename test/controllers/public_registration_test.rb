# frozen_string_literal: true

require "test_helper"

# Self-registration on a public tournament: who may, and when.
class PublicRegistrationTest < ActionDispatch::IntegrationTest
  include RateLimitStore

  setup do
    @tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                          state: :registration_open)
  end

  test "an account without a player cannot register, and creates no guest entries" do
    organizer_only = User.create!(name: "Org Only", email_address: "org-only-#{SecureRandom.hex(3)}@example.com",
                                  password: "password123", organizer: true)
    assert_nil organizer_only.player
    sign_in_user(organizer_only)

    assert_no_difference -> { EventParticipant.count } do
      3.times do
        post tournament_event_participants_path(@tournament), params: { event_participant: { accepted_terms: "1" } }
      end
    end
    assert_redirected_to tournament_path(@tournament)
    assert_equal I18n.t("flash.alert.no_player"), flash[:alert]
  end

  test "registration is refused once the organizer closes it, not only once the swiss starts" do
    @tournament.update_column(:state, "registration_closed") # rubocop:disable Rails/SkipsModelValidations
    sign_in_user(users(:player_one))

    assert_no_difference -> { EventParticipant.count } do
      post tournament_event_participants_path(@tournament), params: { event_participant: { accepted_terms: "1" } }
    end
    assert_redirected_to tournament_path(@tournament)
    assert_equal I18n.t("flash.alert.registration_closed"), flash[:alert]
    assert_raises(Registrations::Closed) { Registrations::Enroll.call(event: @tournament, player: players(:player_one)) }
    assert_raises(ArgumentError) { Registrations::Enroll.call(event: @tournament, player: nil) }
  end

  test "registering is limited to thirty attempts per ten minutes per account" do
    sign_in_user(users(:player_one))
    with_memory_rate_limit_store do
      30.times do
        post tournament_event_participants_path(@tournament), params: { event_participant: { accepted_terms: "1" } }
      end
      post tournament_event_participants_path(@tournament), params: { event_participant: { accepted_terms: "1" } }
      assert_equal I18n.t("flash.alert.try_again_later"), flash[:alert]
    end
  end

  private

  def sign_in_user(user)
    post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
  end
end
