# frozen_string_literal: true

module LeaguesHelper
  # A league player's name, opening their profile when they have an account.
  def league_player(participant)
    user = participant.player&.user
    return participant.name unless user&.handle

    link_to participant.name, profile_path(user.handle, locale: params[:locale]),
            class: "hover:text-accent hover:underline"
  end

  # "Ana won" or "Draw": the result reported at a table and still waiting for a confirmation.
  def league_pending_text(pod)
    pending = pod.pending_result
    return t("leagues.tables.draw") if pending["type"] == "Draw"

    winner = pod.seatings.map(&:event_participant).find { |participant| participant.id == pending["winner_id"] }
    t("leagues.tables.won", name: winner&.name)
  end

  # The tabs of an open-tables league page.
  def league_tabs(league, active)
    %w[about tables mine played standings feed].map do |tab|
      { label: t("leagues.tabs.#{tab}"), active: tab == active,
        path: league_path(league, tab: (tab unless tab == "about"), locale: params[:locale]) }
    end
  end

  # The organizer's league page tabs: the tables to deal with, the players, the feed of results, the standings, the
  # league's details and the form that edits them.
  def organizer_league_tabs(league, active)
    %w[tables players feed standings details edit].map do |tab|
      { label: t("league_desk.tabs.#{tab}"), active: tab == active,
        path: organizer_league_path(league, tab: (tab unless tab == "tables")) }
    end
  end
end
