# frozen_string_literal: true

module Tournaments
  class PlayerSorter
    PREFERRED_POD_SIZE = 4

    def initialize(round)
      @round = round
    end

    # Ranking order (points and tiebreakers). Top cut decides who advances from this order, so it never changes.
    def sorted_players
      players_by_rank = participants.shuffle
      players_by_rank.sort_by.with_index { |p, i| [-p.rank_score, i] }
    end

    # Swiss pairing order: the ranking, with each group of equal match points dealt by seat need (.deal).
    # Only the order inside a points group changes, so pod composition by points is the same.
    def paired_players
      sorted_players.chunk_while { |a, b| a.match_points == b.match_points }.flat_map do |group|
        self.class.deal(group, group.index_with(&:seat_counts))
      end
    end

    # Random pairing order: the whole field (by id, so only the rng decides) shuffled with `rng`, then dealt by
    # seat need as one group. Points play no part.
    def random_players(rng)
      field = participants.sort_by(&:id).shuffle(random: rng)
      self.class.deal(field, field.index_with(&:seat_counts))
    end

    # Need-aware dealing (spec §5.3, measured by grindin:simulate): sort the group by the seat each player needs
    # most (their least-used of seats 1..4, lowest seat on ties), then by fewest seat-1s, keeping the incoming
    # order otherwise; then deal player k to pod k mod P, P = ceil(size / 4), so every pod gets a mix of needs.
    def self.deal(group, seat_counts)
      pods = group.size.ceildiv(PREFERRED_POD_SIZE)
      ranked = group.each_with_index.sort_by { |p, i| [needed_seat(seat_counts[p]), seat_counts[p][1], i] }
      ranked.map(&:first).each_with_index.group_by { |_, k| k % pods }.values.flat_map { |dealt| dealt.map(&:first) }
    end

    def self.needed_seat(counts) = (1..PREFERRED_POD_SIZE).min_by { |seat| [counts[seat], seat] }

    private

    # The round's participants, loaded through the standings (ranking and seat counts in one query).
    def participants
      ids = @round.event_participants.ids.to_set
      EventParticipant.standings_for(@round.event).select { |p| ids.include?(p.id) }
    end
  end
end
