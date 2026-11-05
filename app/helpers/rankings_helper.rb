# frozen_string_literal: true

module RankingsHelper
  QUERY_KEYS = %w[season country organizer play team q tab sort all].freeze

  # The /rankings URL of the current query with changes merged in (nil values drop a key); filter changes reset all=1.
  def rankings_url(changes = {})
    query = request.query_parameters.slice(*QUERY_KEYS).merge(changes.stringify_keys).compact_blank
    rankings_path(**query.symbolize_keys)
  end

  def rankings_filter_fields(board, tab) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength -- one entry per filter
    seasons = board.seasons
    season = board.filters[:season].to_s
    [
      [:q, :search, t(tab == "teams" ? "rankings.filters.search_team" : "rankings.filters.search"), board.filters[:q]],
      [:season, :segment, seasons.map do |year|
        [year.to_s, year.to_s]
      end + [[t("rankings.filters.all_time"), "all"]], season,
       t("rankings.filters.season")],
      [:country, :select, [[t("rankings.filters.all_countries"), ""]] + board.countries.map do |code|
        [country_name(code), code]
      end,
       board.filters[:country], t("rankings.filters.country")],
      [:organizer, :select, [[t("rankings.filters.all_organizers"), ""]] + board.organizers, board.filters[:organizer],
       t("rankings.filters.organizer")],
      [:team, :select, [[t("rankings.filters.all_teams"), ""]] + board.teams.map do |team|
        [team, team]
      end, board.filters[:team],
       t("rankings.filters.team")],
      [:play, :select, rankings_play_options(board), board.filters[:play], t("rankings.filters.format")]
    ]
  end

  # The eight plays, after "All formats" except on the leaderboard (one pool at a time, M15 D6).
  def rankings_play_options(board)
    plays = Event::PLAYS.map { |play| [play_label(play), play] }
    board.leaderboard? ? plays : [[t("rankings.filters.all_formats"), ""]] + plays
  end

  # [[label, value, url without it]] for the active filters (the season only when it is not the default one; the
  # leaderboard's play always, its ✕ going back to multiplayer).
  def rankings_chips(board) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity -- one chip per filter
    filters = board.filters
    chips = []
    season = filters[:season]
    unless season == board.default_season
      chips << [t("rankings.filters.season"), season == :all ? t("rankings.filters.all_time") : season.to_s, :season]
    end
    chips << [t("rankings.filters.country"), country_name(filters[:country]), :country] if filters[:country]
    if filters[:organizer]
      name = board.organizers.find { |_, handle| handle == filters[:organizer] }.first
      chips << [t("rankings.filters.organizer"), name, :organizer]
    end
    chips << [t("rankings.filters.format"), play_label(filters[:play]), :play] if filters[:play]
    chips << [t("rankings.filters.team"), filters[:team], :team] if filters[:team]
    chips << [t("rankings.filters.search_chip"), filters[:q], :q] if filters[:q]
    chips.map { |label, value, key| [label, value, rankings_url(key => nil, all: nil)] }
  end

  # Links to /p/:handle when the viewer may open the profile (one query for participants-only profiles).
  def ranking_visible?(user)
    return false if user&.handle.blank?
    return user.profile_visible_to?(current_user) unless user.visibility == "participants" && authenticated?

    user.id == current_user.id || (!user.anonymized? && ranking_mates.include?(user.id))
  end

  # A points header that sorts by its column (points is the default, so it drops sort=).
  def ranking_sort_link(board, key, label)
    on = board.sort == key
    link_to label, rankings_url(sort: (key unless key == :points), all: nil),
            class: ["hover:text-ink", ("text-ink" if on)], "aria-sort": ("descending" if on)
  end

  def ranking_rank_class(index) = index < 3 ? "text-ink" : "text-muted"

  # "26" or "49.5".
  def ranking_points(value) = number_with_precision(value, precision: 2, strip_insignificant_zeros: true)

  # "+12" in accent, "-8" in danger, "0" muted.
  def ranking_change(change)
    tone =
      if change.positive?
        "text-accent"
      elsif change.negative?
        "text-danger"
      else
        "text-muted"
      end
    tag.span(change.positive? ? "+#{change}" : change.to_s, class: "font-semibold #{tone}", data: { change: true })
  end

  def ranking_best(position)
    return "–" if position.nil?

    t("profiles.rank", ordinal: position.ordinalize, position: position)
  end

  def ranking_percent(value) = value.nil? ? "–" : "#{value}%"

  def ranking_initials(name) = name.split.first(2).pluck(0).join.upcase

  private

  # Users who played an event with the viewer.
  def ranking_mates
    @ranking_mates ||=
      begin
        mine = EventParticipant.joins(:player).where(players: { user_id: current_user.id }).select(:event_id)
        Player.where(id: EventParticipant.where(event_id: mine).select(:player_id)).where.not(user_id: nil)
          .distinct.pluck(:user_id).to_set
      end
  end
end
