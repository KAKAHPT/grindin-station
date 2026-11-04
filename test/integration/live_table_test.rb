# frozen_string_literal: true

require "test_helper"

# The live pages subscribe to their signed streams: "my table" to the participant's, the round page to the round's.
class LiveTableTest < ActionDispatch::IntegrationTest
  setup do
    @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
    @round = @tournament.rounds.create!(type: SwissRound, number: 1)
    @round.update!(published: true)
    @me = @round.pods.order(:number).first.event_participants.first
  end

  test "my table follows the participant's stream, in the page's locale" do
    sign_in(@me.player.user)

    get play_me_path(@tournament.slug)
    assert_select "turbo-cable-stream-source[signed-stream-name=?]",
                  signed(LiveBroadcasts.table_stream(@tournament, @me, :en))
    assert_select "#my_table [data-table-number]"

    get play_me_path(@tournament.slug, locale: "pt")
    assert_select "turbo-cable-stream-source[signed-stream-name=?]",
                  signed(LiveBroadcasts.table_stream(@tournament, @me, :pt))
  end

  test "before pairings the waiting page already follows the stream" do
    @round.update!(published: false)
    sign_in(@me.player.user)

    get play_me_path(@tournament.slug)
    assert_select "turbo-cable-stream-source[signed-stream-name=?]",
                  signed(LiveBroadcasts.table_stream(@tournament, @me, :en))
    assert_select "#my_table", text: /#{I18n.t('play.tables.waiting')}/
  end

  test "the round page follows the round's stream and morph-refreshes, keeping the scroll" do
    sign_in(users(:organizer_user))

    get organizer_tournament_round_path(@tournament, @round)
    assert_select "turbo-cable-stream-source[signed-stream-name=?]", signed(LiveBroadcasts.round_stream(@round.id, :en))
    assert_select "meta[name=turbo-refresh-method][content=morph]"
    assert_select "meta[name=turbo-refresh-scroll][content=preserve]"
    assert_select "[id^=pod_][id$=_state]", count: @round.pods.count
  end

  private

  def signed(streamables)
    Turbo::StreamsChannel.signed_stream_name(streamables)
  end

  def sign_in(user)
    user.update!(password: "password123")
    post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
  end
end
