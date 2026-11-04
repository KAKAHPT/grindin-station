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

  # The last events at the tournament: judge calls, enrolments, check-ins and decklists, newest first,
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
       ([lately_text(:decklist, p), p.updated_at] if decklist_changed?(p))].compact
    end
  end

  def lately_text(kind, participant) = t("organizer.overview.lately.#{kind}", name: participant.name)

  # No decklist timestamp: a decklist changed after enrolment shows at the participant's last change.
  def decklist_changed?(participant)
    participant.decklist.present? && participant.updated_at > participant.created_at + 1.minute &&
      participant.updated_at != participant.checked_in_at
  end

  # "7 / 1 / 0 · bye 7"
  def tournament_points_line(tournament)
    t("organizer.overview.points_line", win: tournament.points_win, draw: tournament.points_draw,
                                        loss: tournament.points_loss, bye: tournament.points_bye)
  end
end
