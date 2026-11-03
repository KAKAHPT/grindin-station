# frozen_string_literal: true

class EventParticipantsController < ApplicationController
  skip_before_action :require_authentication, only: %i[index]
  rescue_from(Registrations::Closed) { redirect_to load_event, alert: t("flash.alert.registration_closed") }
  rescue_from(Registrations::Full) { redirect_to load_event, alert: t("flash.alert.registration_full") }

  def index
    @tournament = load_event
    render layout: "modal"
  end

  def new
    event = load_event
    return redirect_to(event, alert: t("flash.alert.registration_closed")) if event.points_locked?

    @event_participant = EventParticipant.new(event: event, player: current_user.player)
  end

  def edit
    @event = load_event
    @event_participant = load_participant(@event)
  end

  def create
    event = load_event
    @event_participant = EventParticipant.new(event: event, player: current_user.player)
    @event_participant.attributes = event_participant_params
    return render(:new, status: :unprocessable_entity, layout: "modal") unless terms_accepted?

    enroll(event)
  end

  def update
    @event = load_event
    @event_participant = load_participant(@event)
    @event_participant.update(event_participant_params)

    redirect_to @event_participant.event, notice: t("flash.notice.update_successful")
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
    render :new, status: :unprocessable_entity, layout: "modal"
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
    Tournament.find params[:tournament_id]
  end

  def load_participant(event)
    event.event_participants.find_by(player: current_user.player)
  end
end
