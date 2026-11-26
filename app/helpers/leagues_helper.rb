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

  # What each role may do on the organizer's league page (Organizer::LeaguesController): run it (settings and
  # steps), change the roster, enter results. The caster only reads.
  LEAGUE_DESK_ROLES = { run: %w[organizer], roster: %w[organizer judge],
                        score: %w[organizer judge scorekeeper] }.freeze

  def league_desk_can?(what) = staff_role.in?(LEAGUE_DESK_ROLES.fetch(what))

  # The organizer's league page tabs: the tables to deal with, the players, the feed of results, the standings, the
  # league's details and, for who may, the form that edits them and (the owner) the staff.
  def organizer_league_tabs(league, active, owner: false)
    tabs = %w[tables players feed standings details]
    tabs << "edit" if league_desk_can?(:run)
    tabs << "staff" if owner
    tabs.map do |tab|
      { label: t("league_desk.tabs.#{tab}"), active: tab == active,
        path: organizer_league_path(league, tab: (tab unless tab == "tables")) }
    end
  end
end
