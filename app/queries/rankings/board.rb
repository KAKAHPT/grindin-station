# frozen_string_literal: true

module Rankings
  # The /rankings tables (spec M13 D1–D10) read from ranking_contributions and elo_ratings, narrowed by the URL
  # filters. Filters are normalised (unknown values ignored); country and team always match the player's current
  # account (ruling R1), the Teams tab groups by the team stored on the contributions. Ratings never change with the
  # filters (D6): a filtered leaderboard lists the season rating of the players with a matching contribution.
  class Board # rubocop:disable Metrics/ClassLength -- filters, options and three tables of one page
    FORMATS = %w[multiplayer one_v_one].freeze
    SORTS = %i[points events wins top_cuts conversion].freeze
    TEAM_SIZE = 5
    CUT_BONUS = 15
    WIN_BONUS = 30
    PROVISIONAL = 10
    START = 1500
    AVATAR = { avatar_attachment: { blob: { variant_records: { image_attachment: :blob } } } }.freeze

    PointsRow = Data.define(:player, :user, :points, :events, :wins, :top_cuts, :conversion, :best)
    EloRow = Data.define(:player, :user, :rating, :change, :peak, :games, :win_pct, :provisional)
    TeamRow = Data.define(:team, :points, :avg_rating, :players, :events, :wins, :top_cuts)

    # The player's best finish: the lowest final position among the matching events. A derived table with one row
    # per (event, player), so a player entered twice in an event does not multiply the contribution rows.
    POSITIONS = <<~SQL.squish
      LEFT JOIN (SELECT event_id, player_id, MIN(final_position) AS best FROM event_participants
        WHERE NOT waitlisted GROUP BY event_id, player_id) positions
        ON positions.event_id = ranking_contributions.event_id AND positions.player_id = ranking_contributions.player_id
    SQL
    POINTS_COLUMNS = [
      "ranking_contributions.player_id", "SUM(ranking_contributions.points)", "COUNT(*)",
      "COUNT(*) FILTER (WHERE ranking_contributions.won)", "COUNT(*) FILTER (WHERE ranking_contributions.made_cut)",
      "MIN(positions.best)"
    ].map { |column| Arel.sql(column) }.freeze

    # Organizer accounts of the contributions, joined under their own alias (users is the players' accounts).
    ORGANIZERS = <<~SQL.squish
      LEFT JOIN event_organizers organizers ON organizers.id = ranking_contributions.event_organizer_id
      LEFT JOIN users organizer_users ON organizer_users.id = organizers.user_id
    SQL
    OPTION_COLUMNS = [
      "ranking_contributions.season", "users.country", "users.team", "ranking_contributions.team",
      "organizers.id", "organizer_users.name", "organizer_users.handle"
    ].map { |column| Arel.sql(column) }.freeze

    def initialize(params)
      @params = params.to_h.symbolize_keys
    end

    def filters
      @filters ||= {
        season: season, country: pick(:country, countries), organizer: organizer&.last,
        event_organizer_id: organizer&.first, play: pick(:play, FORMATS), team: pick(:team, teams), q: query
      }
    end

    # The current year (D3, always offered, even before it has data), then the other years with contributions,
    # newest first.
    def seasons = @seasons ||= ([default_season] + options[:seasons]).uniq

    def countries = options[:countries]

    def teams = options[:teams]

    # [[name, handle]] of the organizers with contributions, by name.
    def organizers = organizer_options.map { |_, name, handle| [name, handle] }

    def default_season = Date.current.year

    def points
      totals = filtered.joins(POSITIONS).group(:player_id).pluck(*POINTS_COLUMNS)
      players = players_by_id(totals.map(&:first))
      sort_points(totals.map { |id, *figures| points_row(players.fetch(id), *figures) })
    end

    def elo
      matching = filtered.select(:player_id)
      ratings = EloRating.where(player_id: matching, season: rating_season).index_by(&:player_id)
      sort_elo(players(Player.where(id: matching)).map { |player| elo_row(player, ratings[player.id]) })
    end

    def teams_board
      entries = filtered(team_from: :contribution).where.not(team: [nil, ""])
        .pluck(:team, :player_id, :points, :made_cut, :won)
      members = entries.group_by(&:first).transform_values { |rows| rows.group_by(&:second) }
      ratings = team_ratings(members)
      members.map { |team, by_player| team_row(team, by_player, ratings) }
        .sort_by { |row| [-row.points, row.team] }
    end

    def summary
      players, events, organizers, updated_at = filtered.pick(
        *%w[player_id event_id event_organizer_id].map do |column|
          Arel.sql("COUNT(DISTINCT ranking_contributions.#{column})")
        end,
        Arel.sql("(SELECT MAX(elo_ratings.updated_at) FROM elo_ratings)")
      )
      # The same instant as Rankings.last_rebuilt_at, read in the counts query.
      { players: players, events: events, organizers: organizers, updated_at: updated_at&.in_time_zone }
    end

    # The points column to sort by (points unless a known one is asked for).
    def sort = SORTS.find { |key| key.to_s == @params[:sort].to_s } || :points

    private

    def season
      return :all if @params[:season].to_s == "all"

      seasons.find { |year| year.to_s == @params[:season].to_s } || default_season
    end

    def rating_season = filters[:season] == :all ? nil : filters[:season]

    def pick(key, allowed) = allowed.find { |value| value == @params[key].to_s }

    def query = @params[:q].to_s.strip.presence

    def organizer
      handle = @params[:organizer].to_s
      @organizer ||= organizer_options.find { |_, _, value| value == handle }&.values_at(0, 2)
    end

    # [[id, name, handle]] of the organizers with contributions (and a handle), by name.
    def organizer_options = options[:organizers]

    # Seasons with data (newest first), the countries and teams of the ranked players' current accounts (plus the
    # teams stored on contributions) and the organizers, in one query.
    def options
      @options ||=
        option_lists(RankingContribution.left_joins(player: :user).joins(ORGANIZERS).distinct.pluck(*OPTION_COLUMNS))
    end

    def option_lists(rows)
      { seasons: rows.map(&:first).uniq.sort.reverse, countries: sorted(rows.map(&:second)),
        teams: sorted(rows.flat_map { |row| row.values_at(2, 3) }),
        organizers: rows.map { |row| row.last(3) }.uniq.select(&:last).sort_by(&:second) }
    end

    def sorted(values) = values.compact_blank.uniq.sort

    # The contributions matching the filters; the team filter and the search match the account (players' tabs) or
    # the team stored on the contribution (Teams tab, where the search is the team name).
    def filtered(team_from: :user) # rubocop:disable Metrics/AbcSize -- one line per filter
      scope = RankingContribution.left_joins(player: :user)
      scope = scope.where(season: filters[:season]) unless filters[:season] == :all
      scope = scope.where(event_organizer_id: filters[:event_organizer_id]) if filters[:event_organizer_id]
      scope = scope.where(format: filters[:play]) if filters[:play]
      scope = scope.where(users: { country: filters[:country] }) if filters[:country]
      team_from == :user ? player_filters(scope) : team_filters(scope)
    end

    def player_filters(scope)
      scope = scope.where(users: { team: filters[:team] }) if filters[:team]
      return scope unless filters[:q]

      # Handles only of public profiles: hidden ones show no handle.
      scope.where("users.name ILIKE :q OR users.team ILIKE :q OR " \
                  "(users.handle ILIKE :q AND users.visibility = 'public')", q: like(filters[:q]))
    end

    def team_filters(scope)
      scope = scope.where(team: filters[:team]) if filters[:team]
      filters[:q] ? scope.where("ranking_contributions.team ILIKE ?", like(filters[:q])) : scope
    end

    def like(text) = "%#{ActiveRecord::Base.sanitize_sql_like(text)}%"

    def players_by_id(ids) = players(Player.where(id: ids)).index_by(&:id)

    # Players with their accounts in one joined query, then the avatars (attachment, blob, variant records).
    def players(scope)
      scope.eager_load(:user).to_a.tap do |players|
        ActiveRecord::Associations::Preloader.new(records: players.filter_map(&:user), associations: AVATAR).call
      end
    end

    def points_row(player, sum, events, wins, cuts, best) # rubocop:disable Metrics/ParameterLists -- one SQL row
      PointsRow.new(player: player, user: player.user, points: sum, events: events, wins: wins, top_cuts: cuts,
                    conversion: (cuts * 100.0 / events).round, best: best)
    end

    # Established players first (D5), then by rating.
    def sort_elo(rows) = rows.sort_by { |row| [row.provisional ? 1 : 0, -row.rating, row.player.name] }

    def sort_points(rows)
      rows.sort_by { |row| [-row.public_send(sort), -row.points, -row.wins, -row.top_cuts, row.player.name] }
    end

    # A player without a rated pod has no rating row: 1500, no change, provisional.
    def elo_row(player, rating)
      return unrated_row(player) unless rating

      games = rating.games
      EloRow.new(player: player, user: player.user, rating: rating.rating.round,
                 change: (rating.rating - rating.previous_rating).round, peak: rating.peak.round, games: games,
                 win_pct: win_pct(rating.wins, games), provisional: games < PROVISIONAL)
    end

    def win_pct(wins, games) = games.positive? ? (wins * 100.0 / games).round : nil

    def unrated_row(player)
      EloRow.new(player: player, user: player.user, rating: START, change: 0, peak: START, games: 0, win_pct: nil,
                 provisional: true)
    end

    # A player's contribution to a team: ranking points + 15 per top cut + 30 per tournament win (D7).
    def contribution(rows)
      rows.sum { |_, _, points, made_cut, won| points + (made_cut ? CUT_BONUS : 0) + (won ? WIN_BONUS : 0) }
    end

    # The five best contributors of the team, best first: [[player_id, contribution]].
    def counted(by_player)
      by_player.map { |id, rows| [id, contribution(rows)] }.max_by(TEAM_SIZE) { |_, value| value }
    end

    def team_ratings(members)
      ids = members.values.flat_map { |by_player| counted(by_player).map(&:first) }
      EloRating.where(player_id: ids, season: rating_season).pluck(:player_id, :rating).to_h
    end

    # Mean rating of the counted players (1500 for a player without a rating row).
    def average_rating(best, ratings) = (best.sum { |id, _| ratings.fetch(id, START) } / best.size).round

    def team_row(team, by_player, ratings)
      best = counted(by_player)
      rows = by_player.values.flatten(1)
      TeamRow.new(team: team, points: best.sum(&:last), players: by_player.size, events: rows.size,
                  avg_rating: average_rating(best, ratings), wins: rows.count(&:last), top_cuts: rows.count(&:fourth))
    end
  end
end
