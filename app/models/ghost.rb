# frozen_string_literal: true

# The tournament representation of a ghost
class Ghost < EventParticipant
  def number_of_draws
    0
  end

  def number_of_wins
    0
  end

  def match_points
    0
  end

  def match_win_percentage
    event.points_draw.to_f / event.points_win
  end

  def opponents_average_match_points
    0
  end

  def opponents_average_match_win_percentage
    0
  end

  def rank_score
    0
  end
end
