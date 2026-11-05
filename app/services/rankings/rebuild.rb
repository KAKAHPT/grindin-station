# frozen_string_literal: true

module Rankings
  # Recomputes the stored rankings from the finished tournaments and leagues (spec M13 D11), in one
  # transaction: every ranking_contributions row is deleted and reinserted from Contributions; the
  # elo_ratings of each season (start year) and of all time (season nil) are replayed from the events'
  # duels in start order (ties by id) and upserted; rating rows no longer produced are deleted.
  # previous_rating is the rating stored before the rebuild when it changed, otherwise the stored
  # previous_rating (a rebuild with no new games keeps the last change; 1500 for new rows).
  class Rebuild
    BATCH = 500
    START = 1500
    RATING_COLUMNS = %i[rating peak games wins previous_rating updated_at].freeze

    def self.call = new.call

    def initialize
      @now = Time.current
      @events = Event.where(type: %w[Tournament League], state: Tournament.states[:finished])
        .order(:start_time, :id).to_a
    end

    def call
      counts = ApplicationRecord.transaction { [rebuild_contributions, rebuild_ratings] }
      { contributions: counts.first, ratings: counts.last, at: @now }
    end

    private

    def rebuild_contributions
      RankingContribution.delete_all
      rows = @events.flat_map { |event| Contributions.build(event) }
      rows.each_slice(BATCH) do |batch|
        RankingContribution.insert_all!(batch.map { |row| row.merge(created_at: @now, updated_at: @now) }) # rubocop:disable Rails/SkipsModelValidations
      end
      rows.size
    end

    def rebuild_ratings
      rows = rating_rows
      rows.each_slice(BATCH) do |batch|
        EloRating.upsert_all(batch, unique_by: %i[player_id season], record_timestamps: false, # rubocop:disable Rails/SkipsModelValidations
                                    update_only: RATING_COLUMNS)
      end
      EloRating.where(updated_at: ...@now).delete_all
      rows.size
    end

    # One row per player and season (nil = all time) who played a rated pod.
    def rating_rows
      stored = stored_ratings
      season_pods.flat_map do |season, pods|
        replay(pods).to_h.map { |player_id, entry| rating_row(player_id, season, entry, stored[[player_id, season]]) }
      end
    end

    # { season => the duels of every pod of its events, in order }, all time (nil) last.
    def season_pods
      duels = @events.index_with { |event| Duels.for_event(event) }
      seasons = @events.group_by { |event| event.start_time.year }.merge(nil => @events)
      seasons.transform_values { |events| events.flat_map { |event| duels.fetch(event) } }
    end

    # { [player_id, season] => [rating, previous_rating] } as stored before this rebuild.
    def stored_ratings
      EloRating.pluck(:player_id, :season, :rating, :previous_rating)
        .to_h { |player_id, season, rating, previous| [[player_id, season], [rating, previous]] }
    end

    def replay(pods) = Elo.new(start: START).tap { |elo| pods.each { |pod| elo.play_pod(pod) } }

    def rating_row(player_id, season, entry, stored)
      rating = decimal(entry[:rating])
      { player_id: player_id, season: season, rating: rating, peak: decimal(entry[:peak]), games: entry[:games],
        wins: entry[:wins], previous_rating: previous_rating(rating, stored), created_at: @now, updated_at: @now }
    end

    def previous_rating(rating, stored)
      old_rating, old_previous = stored
      return START if old_rating.nil?

      old_rating == rating ? old_previous : old_rating
    end

    def decimal(value) = BigDecimal(value.to_s).round(2)
  end
end
