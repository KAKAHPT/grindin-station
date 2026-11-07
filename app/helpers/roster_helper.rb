# frozen_string_literal: true

# The organizer roster ("desk" view): counters, flat status chips and the drop round.
module RosterHelper
  DESK_CHIP_TONES = {
    ok: "text-accent bg-accent/[0.07]",
    warn: "text-warn bg-warn/[0.07]",
    bad: "text-danger bg-danger/[0.07]",
    info: "text-info bg-info/[0.07]",
    neutral: "text-muted bg-white/[0.05]",
    missing: "text-[#a3adb8] bg-[#a3adb8]/10 border border-dashed border-[#a3adb8]/45"
  }.freeze

  def desk_chip(tone, &block)
    tag.span(class: "inline-flex items-center h-5 px-1.5 rounded text-[10.5px] font-semibold " \
                    "tracking-[0.02em] whitespace-nowrap #{DESK_CHIP_TONES.fetch(tone)}", &block)
  end

  # The chips shown in the Desk column for one participant: attendance, then payment.
  def desk_chips(participant, event)
    safe_join([attendance_chip(participant, event), payment_chip(participant), decklist_chip(participant)], " ")
  end

  def attendance_chip(participant, event)
    return dropped_chip(participant, event) if participant.dropped?
    if participant.waitlisted?
      return desk_chip(:info) { t("organizer.roster.desk.waitlist", position: participant.waitlist_position) }
    end
    return desk_chip(:ok) { t("organizer.roster.desk.checked_in") } if participant.checked_in?

    desk_chip(:warn) { t("organizer.roster.desk.not_checked_in") }
  end

  def dropped_chip(participant, event)
    round = drop_round(participant, event)
    desk_chip(:bad) do
      round ? t("organizer.roster.desk.dropped_round", round: round) : t("organizer.roster.desk.dropped")
    end
  end

  def decklist_chip(participant)
    return desk_chip(:ok) { t("organizer.roster.decklist") } if participant.decklist.present?

    desk_chip(:missing) { t("organizer.roster.no_decklist") }
  end

  def roster_no_decklist_count(event)
    event.event_participants.count { |p| p.playing? && !p.waitlisted? && p.decklist.blank? }
  end

  def payment_chip(participant)
    return desk_chip(:ok) { t("organizer.roster.desk.paid") } if participant.paid?

    desk_chip(:warn) { t("organizer.roster.desk.unpaid") }
  end

  # Number of the last round that had started when the player dropped, or nil.
  def drop_round(participant, event)
    return if participant.dropped_at.nil?

    event.rounds.select { |r| r.started_at && r.started_at <= participant.dropped_at }.map(&:number).max
  end

  def roster_unpaid_count(event)
    event.event_participants.count { |p| p.playing? && !p.waitlisted? && !p.paid? }
  end

  # Registration order (1-based) by participant id.
  def registration_order(event)
    event.event_participants.sort_by { |p| [p.created_at, p.id] }.each.with_index(1).to_h { |p, i| [p.id, i] }
  end
end
