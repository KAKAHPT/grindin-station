# frozen_string_literal: true

class SwissRound < Round
  validates(
    :number,
    {
      presence: true,
      uniqueness: { scope: :event_id },
      numericality: true,
      inclusion: { in: 1.. }
    }
  )

  def display_name
    "Round ##{number}"
  end

  def duration
    event.round_minutes.minutes
  end

  def create_pods
    Tournaments::CreatePodsJob.perform_now(self)
  end

  def last_swiss_round?
    number == event.number_of_swiss_rounds
  end

  # Closing the last swiss round finishes a tournament without a cut; with a cut the organizer makes it.
  def advance_tournament!
    if last_swiss_round?
      event.update!(state: :finished) if event.is_a?(Tournament) && event.number_of_single_elimination_rounds.zero?
      return
    end

    Tournaments::StartSwissRoundJob.perform_now(event)
  end
end
