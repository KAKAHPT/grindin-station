# frozen_string_literal: true

module Feeds
  # {tid, name, updated (epoch seconds), standings: [{rank, name, id, commander, wins, losses, draws, points, winRate,
  # seats, movement}]}; movement is places moved up since the last swiss round (negative = down; null before
  # round 2 closes and once the swiss is over). 1v1 rows have omw, gw, ogw (4 decimals) instead of seats.
  # id is the player's UUID: opaque and stable. Not player.key, which is MD5(e-mail + name): fast to
  # brute-force from a public name, changes on every rename, and survives account removal.
  class Standings
    def self.call(event, updated: Feeds.last_change(event)) = new(event).to_h(updated)

    # Off-waitlist participants in the order of the public standings page: final positions once the
    # event is finished, then playing before dropped, then rank score, then name.
    def self.ranked(event, participants = EventParticipant.standings_for(event))
      final = event.finished?
      participants.reject(&:waitlisted?).sort_by do |p|
        [final && p.final_position ? 0 : 1, (p.final_position if final).to_i, p.playing? ? 0 : 1, -p.rank_score, p.name]
      end
    end

    def initialize(event)
      @event = event
    end

    def to_h(updated)
      { tid: @event.slug, name: @event.name, updated: Feeds.epoch(updated),
        standings: self.class.ranked(@event).each.with_index(1).map { |participant, rank| row(participant, rank) } }
    end

    private

    def row(participant, rank)
      { rank: rank, name: participant.name, id: participant.player_id,
        commander: Feeds.commander(@event, participant),
        wins: participant.number_of_wins, losses: participant.number_of_losses, draws: participant.number_of_draws,
        points: participant.match_points, winRate: participant.win_rate&.round(4),
        movement: participant.movement_since_last_round }.merge(tiebreakers(participant))
    end

    def tiebreakers(participant)
      return { seats: seats(participant.seat_counts) } unless @event.one_v_one?

      { omw: participant.opponents_match_win_rate.round(4), gw: participant.game_win_rate.round(4),
        ogw: participant.opponents_game_win_rate.round(4) }
    end

    # Seats 1-4 always; seat 5 only for someone who sat there (5-player pods).
    def seats(counts)
      seats = (1..4).to_h { |position| [position.to_s, counts[position]] }
      counts[5].positive? ? seats.merge("5" => counts[5]) : seats
    end
  end
end
