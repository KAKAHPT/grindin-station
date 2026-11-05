# frozen_string_literal: true

module Rankings
  # Elo ratings (spec M13 D5): everyone starts at `start`; a duel moves both players by
  # K × (score − expected), computed from their ratings before the duel. The duels of one pod are
  # played at the same time (#play_pod): every delta comes from the ratings before the pod.
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

    def rating(id) = @players.fetch(id, nil)&.fetch(:rating) || @start
    def peak(id) = @players.fetch(id, nil)&.fetch(:peak) || @start
    def games(id) = @players.fetch(id, nil)&.fetch(:games) || 0
    def wins(id) = @players.fetch(id, nil)&.fetch(:wins) || 0
    def provisional?(id) = games(id) < PROVISIONAL_GAMES

    # One duel; score_a is 1 (a won), 0.5 (draw) or 0 (b won).
    def play(id_a, id_b, score_a) = play_pod([[id_a, id_b, score_a]])

    # The duels of one pod ([a, b, score_a] each), all rated from the ratings before the pod.
    def play_pod(duels)
      deltas = Hash.new(0.0)
      duels.each do |id_a, id_b, score_a|
        change = @k * (score_a - expected(rating(id_a), rating(id_b)))
        deltas[id_a] += change
        deltas[id_b] -= change
        record(id_a, score_a)
        record(id_b, 1 - score_a)
      end
      deltas.each { |id, delta| move(id, delta) }
    end

    def to_h = @players.transform_values(&:dup)

    private

    def player(id, rating = @start) = @players[id] ||= { rating: rating, peak: rating, games: 0, wins: 0 }

    def record(id, score)
      entry = player(id)
      entry[:games] += 1
      entry[:wins] += 1 if score == 1
    end

    def move(id, delta)
      entry = player(id)
      entry[:rating] += delta
      entry[:peak] = [entry[:peak], entry[:rating]].max
    end
  end
end
