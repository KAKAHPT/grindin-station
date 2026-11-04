# frozen_string_literal: true

# Builds tournaments with real players and results for tests, without fixtures.
module TournamentBuilder
  extend self

  # Persisted Tournament with `players` participants, put straight into `state`
  # without running the state-transition jobs.
  def build(players:, organizer:, state: :swiss, format: "multiplayer", match_games: 3)
    suffix = SecureRandom.hex(4)
    tournament = Tournament.create!(
      name: "Torneio #{suffix}", event_organizer: organizer, state: :draft,
      start_time: Time.current, end_time: 1.day.from_now, format: format,
      match_games: match_games
    )
    add_players(tournament, players, suffix)
    tournament.update_column(:state, state) # rubocop:disable Rails/SkipsModelValidations
    tournament.reload
  end

  # Records results for the latest round and marks it finished, without advancing the tournament.
  # winners: { pod_number => seat index (0-based) of the winner, or :draw }. Unlisted pods get no results.
  def play_round!(tournament, winners:)
    round = tournament.rounds.order(:number).last
    winners.each do |pod_number, winner|
      round.pods.find_by!(number: pod_number).seatings.each_with_index do |seating, i|
        result_class(winner, i).create!(round: round, event_participant_id: seating.event_participant_id)
      end
    end
    round.update_columns(finished_at: Time.current, published: true) # rubocop:disable Rails/SkipsModelValidations
    round
  end

  # 1v1: writes a Win/Loss (Draw/Draw when equal) pair with the game columns on the latest round's
  # 2-player pods and closes the round. scores: { pod_number => [games_a, games_b] } (seat order).
  def play_1v1_round!(tournament, scores:)
    round = tournament.rounds.order(:number).last
    scores.each do |pod_number, (games_a, games_b)|
      first, second = round.pods.find_by!(number: pod_number).seatings.order(:order).to_a
      record_1v1!(round, first.event_participant_id, games_a, games_b)
      record_1v1!(round, second.event_participant_id, games_b, games_a)
    end
    round.update_columns(finished_at: Time.current, published: true) # rubocop:disable Rails/SkipsModelValidations
    round
  end

  # One player's side of a 1v1 match: Win/Loss by games, Draw when equal.
  def record_1v1!(round, participant_id, won, lost, drawn = 0)
    result_class_for(won <=> lost).create!(round: round, event_participant_id: participant_id,
                                           games_won: won, games_lost: lost, games_drawn: drawn)
  end

  private

  def result_class_for(comparison) = { 0 => Draw, 1 => Win, -1 => Loss }.fetch(comparison)

  def add_players(tournament, count, suffix)
    count.times do |i|
      tournament.event_participants.create!(
        player_name: "Jogador #{i + 1}", player_email: "jogador-#{i + 1}-#{suffix}@example.com",
        accepted_terms: true
      )
    end
  end

  def result_class(winner, seat_index)
    return Draw if winner == :draw

    seat_index == winner ? Win : Loss
  end
end
