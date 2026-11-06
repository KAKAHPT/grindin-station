# frozen_string_literal: true

class EventParticipantsController < ApplicationController # rubocop:disable Metrics/ClassLength -- the player's own entry
  include PublicEvent

  skip_before_action :require_authentication, only: %i[index]
  rescue_from(Registrations::Closed) { redirect_to load_event, alert: t("flash.alert.registration_closed") }
  rescue_from(Registrations::Full) { redirect_to load_event, alert: t("flash.alert.registration_full") }
  rescue_from(Registrations::AlreadyEnrolled) { redirect_to load_event, alert: t("flash.alert.already_enrolled") }

  # Inside the app's modal frame it stays a modal; opened as a page it moved to /t/:slug/standings.
  def index
    @tournament = load_event
    unless turbo_frame_request_id == "modal"
      return redirect_to(play_standings_path(@tournament.slug, locale: params[:locale]))
    end

    @standings = EventParticipant.standings_for(@tournament)
    @standings_in_modal = true
    render layout: "modal"
  end

  def new
    event = load_event
    return redirect_to(event, alert: t("flash.alert.registration_closed")) if event.points_locked?

    @event_participant = EventParticipant.new(event: event, player: current_user.player)
  end

  def edit
    @event = load_event
    return decklist_locked if decklist_locked?

    @event_participant = load_participant(@event)
  end

  def create
    event = load_event
    @event_participant = EventParticipant.new(event: event, player: current_user.player)
    @event_participant.attributes = event_participant_params
    return redirect_to(event, alert: registration_errors) unless terms_accepted? && decklist_given?

    enroll(event)
  end

  def update
    @event = load_event
    return decklist_locked if decklist_locked?

    @event_participant = load_participant(@event)
    if @event.decklist_required && event_participant_params[:decklist].blank?
      return redirect_to @event, alert: t("flash.alert.decklist_required")
    end

    @event_participant.update(event_participant_params)

    redirect_to @event_participant.event, notice: t("flash.notice.update_successful")
  end

  # M16: the player's own check-in, from the event page, while the window is open (Event#check_in_open?).
  def check_in
    @event = load_event
    participant = load_participant(@event)
    unless participant&.enrolled? && @event.check_in_open?
      return redirect_to @event, alert: t("flash.alert.check_in_closed")
    end

    participant.update!(checked_in: true) unless participant.checked_in?
    redirect_to @event, notice: t("flash.notice.checked_in")
  end

  def destroy
    @event = load_event
    @destroyed_participant = load_participant(@event)
    cancel_registration(@destroyed_participant)
    @event_participant = EventParticipant.new

    redirect_to @event, notice: t("flash.notice.registration_canceled")
  end

  private

  # Before the swiss the registration is removed and the waitlist moves up; afterwards it is a drop.
  def cancel_registration(participant)
    return Registrations::Drop.call(participant: participant, by: current_user) if @event.points_locked?

    @event.with_lock do
      freed_place = participant.enrolled?
      participant.destroy
      @event.fill_from_waitlist!(freed_place: freed_place)
    end
  end

  # Players edit their decklist until the swiss starts; staff can still change it from the roster.
  def decklist_locked?
    @event.points_locked?
  end

  # M16: a decklist is optional unless the organizer requires one at registration.
  def decklist_given?
    return true unless @event_participant.event.decklist_required && @event_participant.decklist.blank?

    @event_participant.errors.add(:decklist, t("flash.alert.decklist_required"))
    false
  end

  def decklist_locked
    redirect_to @event, alert: t("flash.alert.decklist_locked")
  end

  def terms_accepted?
    @event_participant.validate
    @event_participant.errors.exclude?(:accepted_terms)
  end

  def enroll(event)
    participant = Registrations::Enroll.call(event: event, player: current_user.player,
                                             decklist: @event_participant.decklist)
    redirect_to event, notice: registration_notice(participant)
  rescue ActiveRecord::RecordInvalid => e
    @event_participant.errors.merge!(e.record.errors)
    redirect_to event, alert: registration_errors
  end

  # The inline form on the event page has no error list of its own: the messages travel as one alert.
  def registration_errors
    @event_participant.errors.map(&:message).uniq.to_sentence
  end

  def registration_notice(participant)
    return t("flash.notice.registration_successful") unless participant.waitlisted?

    t("flash.notice.registration_waitlisted", position: participant.waitlist_position)
  end

  def event_participant_params
    params.expect(event_participant: [
                    :accepted_terms,
                    :decklist
                  ])
  end

  def load_event
    ensure_public!(Tournament.find(params[:tournament_id]))
  end

  def load_participant(event)
    event.event_participants.find_by(player: current_user.player)
  end
end
