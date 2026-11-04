# frozen_string_literal: true

module Tournaments
  # 1v1 cut rounds (spec §5). Bracket positions go by seed and pair i is positions i and size+1-i (1v8, 2v7,
  # 3v6, 4v5). The first cut round eliminates everyone below the cut. Each later round's positions are the
  # previous round's pairs, filled by their winners (Advance). A vacant position (a missing seed, or a winner
  # who dropped) is a walkover: the other player gets an Advance with no seating. Pods are numbered 1..k in
  # bracket order, seats by seed (Pod#ranked_seatings).
  class OneVOneBracket
    def self.call(round) = new(round).call

    def initialize(round)
      @round = round
      @event = round.event
      @cut_size = @event.rounds_info[:top][:players]
      @cut_rounds_played = round.number - @event.number_of_swiss_rounds - 1
    end

    def call
      matches, walkovers = pairs.partition(&:all?)
      build_pods!(matches)

      @round.transaction do
        record!(Eliminated, @eliminated.to_a)
        record!(Advance, walkovers.filter_map { |pair| pair.compact.first })
        @round.pods.each(&:sit_participants!)
      end
    end

    private

    def build_pods!(matches)
      matches.each.with_index(1) { |pair, number| @round.pods.build(number: number, size: 2).candidates = pair }
    end

    def record!(type, players)
      players.each { |player| type.create!(round: @round, event_participant: player) }
    end

    def pairs
      field = @cut_rounds_played.zero? ? first_round_field : later_round_field
      (1..(field.size / 2)).map { |i| [field[i - 1], field[-i]] }
    end

    def active
      @active ||= Tournaments::PlayerSorter.new(@round).sorted_players.sort_by { |player| [-player.rank_score, player.id] }
    end

    def first_round_field
      @eliminated = active.drop(@cut_size)
      Array.new(@cut_size) { |i| active[i] }
    end

    # The previous round's winners (walkovers included) at their bracket positions; a dropped one is vacant.
    def later_round_field
      field = Array.new(@cut_size / (2**@cut_rounds_played))
      by_id = active.index_by(&:id)
      seeds = first_round_seeds
      previous_winner_ids.each { |id| field[position(seeds.fetch(id)) - 1] = by_id[id] }
      field
    end

    def previous_winner_ids
      @event.rounds.find_by!(number: @round.number - 1).results.where(type: "Advance").pluck(:event_participant_id)
    end

    # { participant id => seed } over the first cut round's field (seated or walkover), by swiss seed score.
    def first_round_seeds
      ids = first_round_field_ids
      field = EventParticipant.standings_for(@event).select { |player| ids.include?(player.id) }
      field.sort_by { |player| [-player.one_v_one_seed_score, player.id] }.map(&:id).each.with_index(1).to_h
    end

    def first_round_field_ids
      first = @event.rounds.find_by!(number: @round.number - @cut_rounds_played)
      (first.seatings.pluck(:event_participant_id) + first.byes.pluck(:event_participant_id)).to_set
    end

    # A seed's position this round: every cut round folds position p of a field of n into pair min(p, n+1-p).
    def position(seed)
      size = @cut_size
      @cut_rounds_played.times.reduce(seed) do |position, _|
        folded = [position, size + 1 - position].min
        size /= 2
        folded
      end
    end
  end
end
