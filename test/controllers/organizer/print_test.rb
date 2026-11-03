# frozen_string_literal: true

require "test_helper"

module Organizer
  class PrintTest < ActionDispatch::IntegrationTest
    setup do
      @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer),
                                            state: :swiss)
      @round = @tournament.rounds.first || @tournament.rounds.create!(type: SwissRound, number: 1)
      @pods = @round.pods.order(:number).to_a
      sign_in("organizer_user")
    end

    test "print lists every table with its seats in order" do
      get print_organizer_tournament_round_path(@tournament, @round)

      assert_response :success
      body = response.body
      assert_operator @pods.size, :>, 0
      assert_equal @pods.size, body.scan('class="table"').size
      @pods.each do |pod|
        assert_includes body, "Table #{pod.number}"
        names = pod.seatings.order(:order).map { |s| s.event_participant.name }
        positions = names.map { |n| body.index(ERB::Util.html_escape(n)) }
        assert_equal positions.sort, positions
      end
    end

    test "slips has one QR per table and the player url" do
      get slips_organizer_tournament_round_path(@tournament, @round)

      assert_response :success
      assert_equal @pods.size, response.body.scan("<svg").size
      assert_includes response.body, play_me_url(@tournament.slug)
    end

    test "judges and scorekeepers can open both pages" do
      %w[judge scorekeeper].each do |role|
        user = User.create!(name: role, email_address: "#{role}-#{SecureRandom.hex(3)}@example.com",
                            password: "password123")
        EventStaff.create!(event: @tournament, user: user, role: role)
        sign_in(user)
        get print_organizer_tournament_round_path(@tournament, @round)
        assert_response :success, role
        get slips_organizer_tournament_round_path(@tournament, @round)
        assert_response :success, role
      end
    end

    private

    def sign_in(user)
      user = users(user.to_sym) if user.is_a?(String)
      post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
    end
  end
end
