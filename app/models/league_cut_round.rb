# frozen_string_literal: true

# A round of a league's top cut: the tournament's single elimination, with the league's own field (only the
# players with enough games) and its own next step.
class LeagueCutRound < SingleEliminationRound
  # Out and running at once (the organizer enters the winners on the league page), with a notice to its players.
  def self.start!(league, number)
    round = create!(event: league, number: number, is_finals_round: true, published: true, started_at: Time.current)
    Notify.round(round, kind: "round_published")
    round
  end

  def create_pods
    Leagues::CreateCutPodsJob.perform_now(self)
  end

  # Closing the final finishes the league (final positions, circuit points, rankings).
  def advance_tournament!
    return event.update!(state: :finished) if last_single_elimination_round?

    LeagueCutRound.start!(event, number + 1)
  end
end
