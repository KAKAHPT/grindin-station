# frozen_string_literal: true

module Organizer
  class SeatingsController < OrganizerController
    allow_roles :organizer

    def swap
      tournament = load_tournament
      round = load_round(tournament)
      from_seating = load_seating(round, params[:player], params[:pod])
      to_seating = load_seating(round, params[:with_player], params[:with_pod])

      to_seating.event_participant_id, from_seating.event_participant_id =
        from_seating.event_participant_id, to_seating.event_participant_id
      # The organiser chose these seats: no longer the fair-seating result, so its cost no longer applies.
      [to_seating, from_seating].each { |seating| seating.assign_attributes(assigned_by: "manual", cost: nil) }

      Seating.transaction do
        to_seating.save!
        from_seating.save!
      end

      redirect_to [:organizer, tournament, round.becomes(Round)], notice: t("flash.notice.players_swapped")
    end

    private

    def load_tournament
      Tournament.staffed_by(current_user).find params[:tournament_id]
    end

    def load_round(tournament)
      tournament.rounds.find params[:round_id]
    end

    def load_seating(round, player_id, pod_id)
      round.seatings.find_by(event_participant_id: player_id, pod_id: pod_id)
    end
  end
end
