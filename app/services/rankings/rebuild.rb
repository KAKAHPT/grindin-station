# frozen_string_literal: true

module Rankings
  # Recomputes the stored rankings from the finished tournaments and leagues (spec M13 D11), in one
  # transaction: every ranking_contributions row is deleted and reinserted from Contributions; the
  # elo_ratings of each play pool (Event#play, M15 D6) per season (start year) and for all time (season nil) are
  # replayed from that pool's events' duels in start order (ties by id) and upserted; rating rows no longer
  # produced are deleted.
  # previous_rating is the rating stored before the rebuild when it changed, otherwise the stored
  # previous_rating (a rebuild with no new games keeps the last change; 1500 for new rows).
  # A transaction-level advisory lock keeps two rebuilds (job, rake task) from overlapping.
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
      contributions, ratings = ApplicationRecord.transaction { locked { [rebuild_contributions, rebuild_ratings] } }
      { contributions: contributions, ratings: ratings, at: @now }
    end

    private

    def locked
      ApplicationRecord.connection.execute("SELECT pg_advisory_xact_lock(hashtext('rankings_rebuild'))")
      yield
    end

    def rebuild_contributions
      RankingContribution.delete_all
      rows = unique(@events.flat_map { |event| Contributions.build(event) })
      rows.each_slice(BATCH) do |batch|
        RankingContribution.insert_all!(batch.map { |row| row.merge(created_at: @now, updated_at: @now) }) # rubocop:disable Rails/SkipsModelValidations
      end
      rows.size
    end

    # One row per player and event. A unique index forbids a player twice in an event since M13; this stays as a
    # defensive guard for older data: duplicates keep the entry with the most points (the first on a tie).
    def unique(rows)
      rows.group_by { |row| row.values_at(:player_id, :event_id) }.values
        .map { |group| group.max_by { |row| row[:points] } }
    end

    def rebuild_ratings
      rows = rating_rows
      rows.each_slice(BATCH) do |batch|
        EloRating.upsert_all(batch, unique_by: %i[player_id season play], record_timestamps: false, # rubocop:disable Rails/SkipsModelValidations
                                    update_only: RATING_COLUMNS)
      end
      EloRating.where(updated_at: ...@now).delete_all
      rows.size
    end

    # One row per player, season (nil = all time) and play pool where the player played a rated pod.
    def rating_rows
      stored = stored_ratings
      pool_pods.flat_map do |(season, play), pods|
        replay(pods).to_h.map do |player_id, entry|
          rating_row(player_id, season, play, entry, stored[[player_id, season, play]])
        end
      end
    end

    # { [season, play] => the duels of every pod of that pool's events, in order }; one replay per pool, so a
    # Legacy result never moves a pod rating (D6). All time (season nil) after the seasons.
    def pool_pods
      duels = @events.index_with { |event| Duels.for_event(event) }
      @events.group_by(&:play).flat_map do |play, events|
        seasons = events.group_by { |event| event.start_time.year }.merge(nil => events)
        seasons.map { |season, pool| [[season, play], pool.flat_map { |event| duels.fetch(event) }] }
      end
    end

    # { [player_id, season, play] => [rating, previous_rating] } as stored before this rebuild.
    def stored_ratings
      EloRating.pluck(:player_id, :season, :play, :rating, :previous_rating)
        .to_h { |player_id, season, play, rating, previous| [[player_id, season, play], [rating, previous]] }
    end

    def replay(pods) = Elo.new(start: START).tap { |elo| pods.each { |pod| elo.play_pod(pod) } }

    def rating_row(player_id, season, play, entry, stored)
      rating = decimal(entry[:rating])
      { player_id: player_id, season: season, play: play, rating: rating, peak: decimal(entry[:peak]),
        games: entry[:games], wins: entry[:wins], previous_rating: previous_rating(rating, stored), created_at: @now,
        updated_at: @now }
    end

    def previous_rating(rating, stored)
      old_rating, old_previous = stored
      return START if old_rating.nil?

      old_rating == rating ? old_previous : old_rating
    end

    def decimal(value) = BigDecimal(value.to_s).round(2)
  end
end
