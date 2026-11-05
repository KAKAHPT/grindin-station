# frozen_string_literal: true

module Rankings
  # Elo ratings (spec M13 D5): everyone starts at `start`; a duel moves both players by
  # K × (score − expected), computed from their ratings before the duel. The duels of one pod are
  # played at the same time (#play_pod): every delta comes from the ratings before the pod.
  # games and wins count pods (ruling R7): one game per pod played, a win when the player scored 1
  # against every opponent in it (the pod winner; the match winner in 1v1).
  class Elo
    PROVISIONAL_GAMES = 10

    # ratings: optional starting ratings by id (any other id starts at `start`).
    def initialize(k: 32, start: 1500, ratings: {}) # rubocop:disable Naming/MethodParameterName
      @k = k
      @start = start.to_f
      @players = {}
      ratings.each { |id, rating| player(id, rating.to_f) }
    end

    def expected(rating_a, rating_b) = 1 / (1 + (10**((rating_b - rating_a) / 400.0)))

    def rating(id) = @players.dig(id, :rating) || @start
    def peak(id) = @players.dig(id, :peak) || @start
    def games(id) = @players.dig(id, :games) || 0
    def wins(id) = @players.dig(id, :wins) || 0
    def provisional?(id) = games(id) < PROVISIONAL_GAMES

    # One duel; score_a is 1 (a won), 0.5 (draw) or 0 (b won).
    def play(id_a, id_b, score_a) = play_pod([[id_a, id_b, score_a]])

    # The duels of one pod ([a, b, score_a] each), all rated from the ratings before the pod.
    def play_pod(duels)
      deltas, scores = tally(duels)
      scores.each { |id, list| move(id, deltas[id], won: list.all?(1)) }
    end

    def to_h = @players.transform_values(&:dup)

    private

    # Rating change per player (from the ratings before the pod) and each player's scores in the pod.
    def tally(duels)
      deltas = Hash.new(0.0)
      scores = Hash.new { |hash, id| hash[id] = [] }
      duels.each do |id_a, id_b, score_a|
        change = change(id_a, id_b, score_a)
        deltas[id_a] += change
        deltas[id_b] -= change
        scores[id_a] << score_a
        scores[id_b] << (1 - score_a)
      end
      [deltas, scores]
    end

    def change(id_a, id_b, score_a) = @k * (score_a - expected(rating(id_a), rating(id_b)))

    def player(id, rating = @start) = @players[id] ||= { rating: rating, peak: rating, games: 0, wins: 0 }

    def move(id, delta, won:)
      entry = player(id)
      entry[:games] += 1
      entry[:wins] += 1 if won
      entry[:rating] += delta
      entry[:peak] = [entry[:peak], entry[:rating]].max
    end
  end
end
