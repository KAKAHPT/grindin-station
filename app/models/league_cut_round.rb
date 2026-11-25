# frozen_string_literal: true

# A round of a league's top cut: the tournament's single elimination, with the league's own field (only the
# players with enough games) and its own next step.
class LeagueCutRound < SingleEliminationRound
  def create_pods
    Leagues::CreateCutPodsJob.perform_now(self)
  end

  # Closing the final finishes the league (final positions, circuit points, rankings).
  def advance_tournament!
    return event.update!(state: :finished) if last_single_elimination_round?

    LeagueCutRound.create!(event: event, number: number + 1, is_finals_round: true)
  end
end
