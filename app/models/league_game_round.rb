# frozen_string_literal: true

# One game of a league played at a table the players opened: a round with a single pod, so the results
# (one per round and player) and the reporting flow work as in a tournament. Never paired automatically.
class LeagueGameRound < Round
  def create_pods; end

  def display_name = I18n.t("leagues.game", n: number)

  def duration = event.round_minutes.minutes
end
