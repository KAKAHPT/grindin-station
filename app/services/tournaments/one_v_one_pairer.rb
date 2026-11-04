# frozen_string_literal: true

module Tournaments
  # 1v1 Swiss pairings (spec §3): an odd field gives a bye (Advance, 2-0) to the lowest-ranked player without
  # one; round 1 is a seeded shuffle; later rounds pair inside each match-points group in a seeded random
  # order (the last swiss round top-down by rank), an odd group sending its lowest-ranked player down.
  # Rematches are then repaired with the same escalating points gap as CreatePodsJob.
  class OneVOnePairer
    def self.call(round) = new(round).call

    def initialize(round)
      @round = round
      @event = round.event
      @rng = Random.new(Digest::SHA256.hexdigest([@event.seed.to_i, round.number, "1v1"].join("-")).to_i(16))
    end

    def call
      raise ArgumentError, "round #{@round.number} already has pods" if @round.pods.any?

      players = ranked_players
      bye = bye_player(players)
      build_pods!(pairs(players - [bye]))
      repair_rematches!

      @round.transaction do
        Advance.create!(round: @round, event_participant: bye, games_won: 2) if bye
        @round.pods.each(&:sit_participants!)
      end
    end

    private

    # Active participants, best first; ids break the (salted, so unlikely) rank ties.
    def ranked_players
      ids = @round.event_participants.ids.to_set
      EventParticipant.standings_for(@event).select { |player| ids.include?(player.id) }
        .sort_by { |player| [-player.rank_score, player.id] }
    end

    def bye_player(players)
      return if players.size.even?

      players.rfind { |player| player.number_of_byes.zero? } || players.last
    end

    def pairs(players)
      return players.sort_by(&:id).shuffle(random: @rng).each_slice(2).to_a if @round.number == 1

      carried = nil
      players.chunk_while { |a, b| a.match_points == b.match_points }.flat_map do |group|
        group.unshift(carried) if carried
        carried = group.size.odd? ? group.pop : nil
        pair_group(group)
      end
    end

    # Seeded random order; the last swiss round keeps the rank order (top-down power pairing).
    def pair_group(group)
      (last_swiss_round? ? group : group.shuffle(random: @rng)).each_slice(2).to_a
    end

    def last_swiss_round? = @round.number == @event.number_of_swiss_rounds

    def build_pods!(pairs)
      pairs.each.with_index(1) do |pair, number|
        @round.pods.build(number: number, size: 2).candidates = pair
      end
    end

    # Same gaps as CreatePodsJob#repair_rematches!: same points, a draw, a win, two wins, ..., then any.
    def repair_rematches!
      wins = (1...@round.number).map { |count| count * @event.points_win }
      gaps = ([0, @event.points_draw] + wins).uniq.sort + [Float::INFINITY]
      gaps.each do |gap|
        break if Tournaments::RematchRepair.new(@round, max_point_gap: gap).repair!.zero?
      end
    end
  end
end
