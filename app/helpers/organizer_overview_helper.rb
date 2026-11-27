# frozen_string_literal: true

# The Overview tab of the organizer tournament page: counters, format and the latest activity.
module OrganizerOverviewHelper
  LATELY_SHOWN = 6

  # Overview counters from the loaded participants.
  def tournament_counters(tournament)
    participants = tournament.event_participants
    { enrolled: participants.count(&:enrolled?), waitlist: participants.count { |p| p.playing? && p.waitlisted? },
      checked_in: participants.count { |p| p.enrolled? && p.checked_in? },
      unpaid: roster_unpaid_count(tournament), no_decklist: roster_no_decklist_count(tournament) }
  end

  # The last events at the tournament: judge calls, enrolments, check-ins and drops, newest first,
  # as [text, time]. Participants come loaded; judge calls take one query (plus their pods).
  def tournament_lately(tournament)
    calls = tournament.judge_calls.includes(:pod).order(created_at: :desc).limit(LATELY_SHOWN).map { |c| call_event(c) }
    (calls + participant_events(tournament.event_participants)).sort_by { |_, time| -time.to_f }.first(LATELY_SHOWN)
  end

  def call_event(call)
    text =
      if call.pod then t("organizer.overview.lately.judge_call_table", table: call.pod.number)
      else t("organizer.overview.lately.judge_call")
      end
    [text, call.created_at]
  end

  def participant_events(participants)
    participants.flat_map do |p|
      [[lately_text(:enrolled, p), p.created_at],
       ([lately_text(:checked_in, p), p.checked_in_at] if p.checked_in_at),
       ([lately_text(:dropped, p), p.dropped_at] if p.dropped? && p.dropped_at)].compact
    end
  end

  def lately_text(kind, participant) = t("organizer.overview.lately.#{kind}", name: participant.name)

  # "7 / 1 / 0 · bye 7"
  # The band at the top of the Overview: what the organizer does next, as { title:, hint:, action: } (action only
  # for a role that may do it); nil for a canceled event.
  def overview_next_step(tournament, counters, manager:)
    state = tournament.state
    return if state == "canceled"

    { title: t("organizer.overview.next.#{state}.title"),
      hint: t("organizer.overview.next.#{state}.hint", **counters.slice(:enrolled, :checked_in, :no_decklist)),
      action: overview_next_action(tournament, manager) }
  end

  def overview_next_action(tournament, manager)
    if tournament.finished?
      return link_to(t("organizer.overview.next.finished.action"), play_standings_path(tournament.slug),
                     target: "_blank", rel: "noopener", class: button_classes(:secondary, size: :sm))
    end
    next_state = tournament_next_state(tournament)
    return overview_state_button(tournament, next_state) if next_state && manager

    rounds = rounds_tab_path(tournament)
    link_to(t("organizer.overview.next.rounds"), rounds, class: button_classes(:primary, size: :sm)) if rounds
  end

  def overview_state_button(tournament, next_state)
    button_to(transition_for(state: next_state), organizer_tournament_path(tournament),
              method: :patch, params: { tournament: { state: next_state } },
              data: { turbo_confirm: state_confirm(tournament, next_state) },
              class: button_classes(:primary, size: :sm))
  end

  def tournament_points_line(tournament)
    t("organizer.overview.points_line", win: tournament.points_win, draw: tournament.points_draw,
                                        loss: tournament.points_loss, bye: tournament.points_bye)
  end
end
