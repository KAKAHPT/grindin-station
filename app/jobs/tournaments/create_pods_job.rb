# frozen_string_literal: true

module Tournaments
  # Job to create pods for a round
  class CreatePodsJob < ApplicationJob
    def perform(round)
      return Tournaments::OneVOnePairer.call(round) if round.event.one_v_one?

      @round = round
      raise ArgumentError, "round #{@round.number} already has pods or results" if already_paired?

      byes = build_pods!
      match_according_to_strategy!
      repair_rematches!
      sit!(byes)
    end

    private

    # Builds the pods for the field, takes the byes from the bottom of the ranking (before dealing by seat need),
    # deals the rest into the pairing order and returns the byes.
    def build_pods!
      sorter = Tournaments::PlayerSorter.new(@round)
      ranked = random? ? sorter.random_field(pairing_rng) : sorter.sorted_players
      shape = Tournaments::UnevenPodGenerator.new(@round).generate_pods!(ranked.size)
      byes = pick_byes(ranked, shape[:byes])
      @players_by_rank = pairing_order(sorter, ranked - byes)
      byes
    end

    def sit!(byes)
      @round.transaction do
        byes.each { |participant| Advance.create!(round: @round, event_participant: participant) }
        @round.pods.each(&:sit_participants!)
      end
    end

    # Pods, or a leftover bye result, mean the round was paired: a second call would hand out more byes.
    def already_paired? = @round.pods.any? || @round.all_results.exists?

    # Walks the ranking from the end and takes the player shortest on games (byes plus pods of 3 so far);
    # ties go to the later position, so the lowest ordered player gets the bye. Repeats for each bye.
    def pick_byes(order, count)
      remaining = order.dup
      Array.new(count) do
        bye = remaining.reverse.min_by.with_index { |player, i| [player.short_count, i] }
        remaining.delete(bye)
      end
    end

    # Swiss and power feed the ranking (points groups dealt by seat need); random feeds the seeded shuffled field.
    def pairing_order(sorter, field)
      random? ? sorter.random_players(pairing_rng, field) : sorter.paired_players(field)
    end

    def random? = @round.event.random_pairing?

    def pairing_rng
      Random.new(Digest::SHA256.hexdigest("#{@round.event.seed || 0}:#{@round.number}:pairing")[0, 8].hex)
    end

    def match_according_to_strategy!
      case load_strategy
      when :spread
        Tournaments::Strategies::SpreadMatcher.new(@round, @players_by_rank).match_players!
      when :forced, :standard
        Tournaments::Strategies::SwissMatcher.new(@round, @players_by_rank).match_players!
      end
    end

    # Every strategy repairs with an escalating points gap: same points first, then a draw, a win, two wins, ...,
    # and any gap only as a last resort, stopping as soon as no rematch is left. Nobody leaves their points group
    # while a swap inside it fixes the rematch, so the leaders stay at the top tables.
    # NOTE: grindin:simulate (Tournaments::SeatSimulator) skips this repair, so its seat numbers assume the repair
    # does not move players far from the tables the pairing gave them.
    def repair_rematches!
      rematch_gaps.each do |gap|
        break if Tournaments::RematchRepair.new(@round, max_point_gap: gap).repair!.zero?
      end
    end

    # Random pairing ignores points, so its repair may swap anyone.
    def rematch_gaps
      event = @round.event
      return [Float::INFINITY] if event.random_pairing?

      wins = (1...@round.number).map { |count| count * event.points_win }
      ([0, event.points_draw] + wins).uniq.sort + [Float::INFINITY]
    end

    # Rounds beyond the thresholds table play as :standard.
    def load_strategy
      @round.event.rounds_info[:rounds][@round.number - 1]&.values&.first || :standard
    end
  end
end
