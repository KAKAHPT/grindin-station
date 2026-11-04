# frozen_string_literal: true

module Profiles
  # A player's finished events, newest first, for the public profile. A fixed number of queries
  # whatever the number of events: participations with their events and results, field sizes, seats.
  class History
    Row = Data.define(:event, :position, :participants, :wins, :losses, :draws, :seats, :decklist_visible, :decklist)

    def self.call(user:) = new(user).call

    def initialize(user)
      @user = user
    end

    def call
      return [] unless @user.player

      participations = finished_participations
      return [] if participations.empty?

      sizes = field_sizes(participations)
      seats = seat_counts(participations)
      participations.map { |participation| row(participation, sizes, seats) }
    end

    private

    def finished_participations
      @user.player.event_participations.joins(:event)
        .where(events: { state: Tournament.states[:finished] })
        .includes(:event, :results).order("events.start_time DESC").to_a
    end

    # Players who held a place (waitlisted entries never played).
    def field_sizes(participations)
      EventParticipant.where(event_id: participations.map(&:event_id), waitlisted: false).group(:event_id).count
    end

    # Multiplayer events only: 1v1 seats are random and never shown.
    def seat_counts(participations)
      ids = participations.reject { |participation| participation.event.one_v_one? }.map(&:id)
      Seating.joins(pod: :round).where(event_participant_id: ids, rounds: { type: "SwissRound" })
        .where("rounds.finished_at IS NOT NULL OR rounds.published = TRUE")
        .group(:event_participant_id, :order).count
        .each_with_object({}) do |((participant_id, position), times), all|
          (all[participant_id] ||= EventParticipant.empty_seat_counts)[position] = times
        end
    end

    # nil for 1v1 (no seats shown).
    def seats_of(participation, seats)
      seats.fetch(participation.id) { EventParticipant.empty_seat_counts } unless participation.event.one_v_one?
    end

    def row(participation, sizes, seats)
      event = participation.event
      visible = event.show_decklists && event.finished? && participation.decklist.present?
      Row.new(event: event, position: participation.final_position, participants: sizes.fetch(event.id, 0),
              wins: participation.number_of_wins, losses: participation.number_of_losses,
              draws: participation.number_of_draws,
              seats: seats_of(participation, seats),
              decklist_visible: visible, decklist: (participation.decklist if visible))
    end
  end
end
