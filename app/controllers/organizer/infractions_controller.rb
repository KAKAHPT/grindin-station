# frozen_string_literal: true

module Organizer
  class InfractionsController < OrganizerController
    layout "modal"
    allow_roles :organizer, :judge

    def index
      @event_participant = load_tournament.event_participants.find(params[:event_participant_id])
      @infractions = Infraction.where(
        player_id: @event_participant.player_id,
        event_id: @event_participant.event_id
      )
    end

    def new
      player = load_player
      pod = load_pod
      event = pod&.event || load_tournament
      @infraction = Infraction.new(player: player, pod: pod, event: event)
    end

    def create
      @infraction = Infraction.new(event: load_tournament)
      @infraction.attributes = infraction_params
      participant = check_event_scope!(@infraction.player_id, @infraction.pod_id)

      if @infraction.save
        audit_infraction(:infraction_added, participant)
        redirect_to [:organizer, @infraction.event, :event_participants, { layout: "application" }],
                    notice: t("flash.notice.infraction_added")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      event = load_tournament
      event_participant = event.event_participants.includes(:player).find(
        params[:event_participant_id]
      )
      @infraction = Infraction.find_by!(event: event, player: event_participant.player, id: params[:id])
      message =
        if @infraction.destroy
          audit_infraction(:infraction_removed, event_participant)
          { notice: "Infraction removed!" }
        else
          { alert: "Error removing infraction!" }
        end

      redirect_to [:organizer, @infraction.event, :event_participants, { layout: "application" }], **message
    end

    private

    def infraction_params
      params.expect(infraction: %i[player_id pod_id kind category description penalty])
    end

    def audit_infraction(action, participant)
      Audit.record(action, subject: @infraction, event: @infraction.event, penalty: @infraction.penalty,
                           participant_id: participant.id)
    end

    # The player and pod must belong to this event (404 otherwise); returns the player's participation.
    def check_event_scope!(player_id, pod_id)
      participant = load_tournament.event_participants.find_by!(player_id: player_id)
      load_tournament.pods.find(pod_id) if pod_id.present?
      participant
    end

    def load_player
      load_tournament.event_participants.find_by!(player_id: params[:player_id]).player
    end

    def load_pod
      load_tournament.pods.find(params[:pod_id]) if params[:pod_id].present?
    end

    def load_tournament
      @load_tournament ||= Tournament.staffed_by(current_user).find params[:tournament_id]
    end
  end
end
