# frozen_string_literal: true

require "test_helper"

module Feeds
  class StandingsTest < ActiveSupport::TestCase
    include FeedTournament

    setup { build_feed_tournament }

    test "ranks the closed round: three winners, then the four drawers, then the nine losers" do
      feed = Feeds::Standings.call(@t)
      rows = feed[:standings]

      assert_equal @t.slug, feed[:tid]
      assert_equal @t.name, feed[:name]
      assert_equal (1..16).to_a, rows.pluck(:rank)
      assert_equal ([7] * 3) + ([1] * 4) + ([0] * 9), rows.pluck(:points)

      winners = [seated(@round1, 1)[0], seated(@round1, 2)[1], seated(@round1, 4)[3]]
      assert_equal winners.map(&:name).sort, rows.first(3).pluck(:name).sort
      assert_equal seated(@round1, 3).map(&:name).sort, rows[3, 4].pluck(:name).sort

      assert_equal([[1, 0, 0, 1.0]] * 3, rows.first(3).map { |r| r.values_at(:wins, :losses, :draws, :winRate) })
      assert_equal([[0, 0, 1, 0.0]] * 4, rows[3, 4].map { |r| r.values_at(:wins, :losses, :draws, :winRate) })
      assert_equal([[0, 1, 0, 0.0]] * 9, rows.last(9).map { |r| r.values_at(:wins, :losses, :draws, :winRate) })
    end

    test "seats count the closed and the published round, one seat each" do
      rows = Feeds::Standings.call(@t)[:standings].index_by { |row| row[:id] }
      seat_of =
        lambda do |round, participant|
          Seating.joins(:pod).find_by!(pods: { round_id: round.id }, event_participant: participant).order
        end

      @t.event_participants.includes(:player).find_each do |participant|
        expected = { "1" => 0, "2" => 0, "3" => 0, "4" => 0 }
        expected[seat_of.call(@round1, participant).to_s] += 1
        expected[seat_of.call(@round2, participant).to_s] += 1
        assert_equal expected, rows.fetch(participant.player_id)[:seats], participant.name
      end
    end

    test "the id is the opaque player id and updated is epoch seconds" do
      feed = Feeds::Standings.call(@t)
      ids = @t.event_participants.pluck(:player_id)

      assert_equal ids.sort, feed[:standings].pluck(:id).sort
      assert(feed[:standings].none? { |row| row[:id].in?(Player.where(id: ids).pluck(:key)) })
      assert_kind_of Integer, feed[:updated]
      assert_equal Feeds.last_change(@t).to_i, feed[:updated]
    end

    test "uses the player id as id and keeps commanders out unless the event shows them" do
      participant = seated(@round1, 1).first
      participant.update_columns(decklist: "Tymna / Thrasios") # rubocop:disable Rails/SkipsModelValidations
      row = Feeds::Standings.call(@t)[:standings].find { |r| r[:id] == participant.player_id }
      assert_equal "", row[:commander]

      @t.update_columns(show_commanders_in_standings: true) # rubocop:disable Rails/SkipsModelValidations
      row = Feeds::Standings.call(@t.reload)[:standings].find { |r| r[:id] == participant.player_id }
      assert_equal "Tymna / Thrasios", row[:commander]
    end

    test "a decklist link is never a commander" do
      @t.update_columns(show_commanders_in_standings: true) # rubocop:disable Rails/SkipsModelValidations
      participant = seated(@round1, 1).first
      participant.update_columns(decklist: "https://moxfield.com/decks/abc") # rubocop:disable Rails/SkipsModelValidations
      row = Feeds::Standings.call(@t.reload)[:standings].find { |r| r[:id] == participant.player_id }
      assert_equal "", row[:commander]
    end

    test "waitlisted players are left out and winRate is null before any game" do
      user = User.create!(name: "Espera", email_address: "espera-#{SecureRandom.hex(3)}@example.com",
                          password: "password123")
      @t.event_participants.create!(player: user.player, accepted_terms: true, waitlisted: true, waitlist_position: 1)
      fresh = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                      state: :registration_closed)

      assert_equal 16, Feeds::Standings.call(@t.reload)[:standings].size
      assert_equal [nil] * 4, Feeds::Standings.call(fresh)[:standings].pluck(:winRate)
    end

    test "multiplayer rows keep their keys: seats and no 1v1 rates" do
      row = Feeds::Standings.call(@t)[:standings].first

      assert_equal %i[rank name id commander wins losses draws points winRate movement seats], row.keys
    end

    test "1v1 rows carry OMW, GW and OGW to 4 decimals and no seats" do
      t = build_1v1_feed_tournament
      rows = Feeds::Standings.call(t)[:standings]
      winner = rows.first

      assert_equal %i[rank name id commander wins losses draws points winRate movement omw gw ogw], winner.keys
      assert_equal [1, 0, 0, 3], winner.values_at(:wins, :losses, :draws, :points)
      assert_equal [0.33, 0.6667, 0.3333], winner.values_at(:omw, :gw, :ogw)
      assert(rows.all? { |row| [row[:omw], row[:gw], row[:ogw]].all?(Float) })
    end

    test "movement is null until two swiss rounds have closed and after the swiss, else places moved up" do
      ::Standings::Snapshot.call(@t, @round1)
      assert(Feeds::Standings.call(@t)[:standings].all? { |row| row.key?(:movement) && row[:movement].nil? })

      first, third = @t.standings_snapshots.where(rank: [1, 3]).order(:rank).map(&:event_participant)
      swapped = { first.id => 3, third.id => 1 }
      @t.standings_snapshots.find_each do |row|
        @t.standings_snapshots.create!(round_number: 2, event_participant_id: row.event_participant_id,
                                       rank: swapped.fetch(row.event_participant_id, row.rank))
      end

      rows = Feeds::Standings.call(@t)[:standings].index_by { |row| row[:id] }
      assert_equal(-2, rows.fetch(first.player_id)[:movement])
      assert_equal 2, rows.fetch(third.player_id)[:movement]
      assert_equal [0] * 14, rows.except(first.player_id, third.player_id).values.pluck(:movement)

      @t.update_column(:state, Tournament.states[:single_elimination]) # rubocop:disable Rails/SkipsModelValidations
      assert(Feeds::Standings.call(@t.reload)[:standings].all? { |row| row[:movement].nil? })
    end
  end
end
