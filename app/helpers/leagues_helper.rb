# frozen_string_literal: true

module LeaguesHelper
  # A league player's name, opening their profile when they have an account.
  def league_player(participant)
    user = participant.player&.user
    return participant.name unless user&.handle

    link_to participant.name, profile_path(user.handle, locale: params[:locale]),
            class: "hover:text-accent hover:underline"
  end

  # The tabs of an open-tables league page.
  def league_tabs(league, active)
    %w[about tables mine played standings].map do |tab|
      { label: t("leagues.tabs.#{tab}"), active: tab == active,
        path: league_path(league, tab: (tab unless tab == "about"), locale: params[:locale]) }
    end
  end

  # The organizer's league page tabs: the tables to deal with (badge: how many wait for the organizer), the
  # players and the league's details.
  def organizer_league_tabs(league, active, waiting: 0)
    badges = { "tables" => (waiting if waiting.positive?), "players" => league.event_participants.count(&:enrolled?) }
    %w[tables players details].map do |tab|
      { label: t("league_desk.tabs.#{tab}"), active: tab == active, badge: badges[tab],
        path: organizer_league_path(league, tab: (tab unless tab == "tables")) }
    end
  end
end
