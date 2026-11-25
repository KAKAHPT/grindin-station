# frozen_string_literal: true

module Scoring
  # A league's standings by wager. Everyone starts with the league's starting_points; at each game every
  # player stakes wager_percentage % of the points they hold at that moment. A single winner takes the pot.
  # When everyone draws, the league's draw_rule decides: "split" shares the pot equally, "lost" gives it to
  # nobody. The games are replayed in the order they ended, from scratch, after every final result,
  # correction or cancelled table.
  class PointWager
    def initialize(event)
      @event = event
      @percent = (event.wager_percentage || 0).to_d
    end

    def recalculate_all!
      participants = @event.event_participants.to_a
      scores = participants.to_h { |participant| [participant.id, @event.starting_points.to_d] }
      settled_pods.each { |pod, results| play(pod, results, scores) }
      participants.each do |participant|
        score = scores.fetch(participant.id).round(2)
        next if participant.league_score == score

        participant.update_columns(league_score: score, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      end
    end

    private

    # [pod, { participant id => current result }] of every league game with a result for each seat, in the
    # order the games ended.
    def settled_pods
      rounds = @event.rounds.play_rounds.includes(:results, pods: :seatings)
        .order(Arel.sql("COALESCE(rounds.finished_at, rounds.created_at)"), :number)
      rounds.flat_map do |round|
        results = round.results.index_by(&:event_participant_id)
        round.pods.filter_map do |pod|
          seated = pod.seatings.map(&:event_participant_id)
          [pod, results.slice(*seated)] if seated.any? && seated.all? { |id| results.key?(id) }
        end
      end
    end

    def play(_pod, results, scores)
      stakes = results.keys.index_with { |id| (scores.fetch(id) * @percent / 100).round(2) }
      winners = results.select { |_, result| result.is_a?(Win) }.keys
      stakes.each { |id, stake| scores[id] -= stake }
      pot = stakes.values.sum

      if winners.one? then scores[winners.first] += pot
      elsif @event.draw_rule == "split" then stakes.each_key { |id| scores[id] += pot / stakes.size }
      end
    end
  end
end
