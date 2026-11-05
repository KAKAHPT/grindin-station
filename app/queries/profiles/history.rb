# frozen_string_literal: true

module Profiles
  # A player's finished events, newest first, for the public profile. A fixed number of queries
  # whatever the number of events: participations joined to their events, circuits and organizers, results,
  # field sizes, swiss seats, cut participations and (for tournaments without a set cut) enrolled counts.
  class History
    Row = Data.define(:event, :position, :participants, :wins, :losses, :draws, :seats, :decklist_visible, :decklist,
                      :games, :made_cut, :cut_size, :commander, :organizer_name, :format_line, :season, :round_seats)

    def self.call(user:) = new(user).call

    def initialize(user)
      @user = user
    end

    def call
      return [] unless @user.player

      participations = finished_participations
      return [] if participations.empty?

      context = { sizes: field_sizes(participations), round_seats: round_seats(participations),
                  cut_ids: cut_ids(participations), cut_sizes: cut_sizes(participations) }
      participations.map { |participation| row(participation, context) }
    end

    private

    def finished_participations
      @user.player.event_participations.where(events: { state: Tournament.states[:finished] })
        .eager_load(event: [:circuit, { event_organizer: :user }]).preload(:results)
        .order("events.start_time DESC").to_a
    end

    # Players who held a place (waitlisted entries never played).
    def field_sizes(participations)
      EventParticipant.where(event_id: participations.map(&:event_id), waitlisted: false).group(:event_id).count
    end

    # { participant id => [seat of swiss round 1, seat of round 2, ...] } over the finished or published swiss
    # rounds. Multiplayer events only: 1v1 seats are random and never shown.
    def round_seats(participations)
      ids = participations.reject { |participation| participation.event.one_v_one? }.map(&:id)
      Seating.joins(pod: :round).where(event_participant_id: ids, rounds: { type: "SwissRound" })
        .where("rounds.finished_at IS NOT NULL OR rounds.published = TRUE")
        .pluck(:event_participant_id, "rounds.number", :order)
        .group_by(&:first).transform_values { |seats| seats.sort_by { |_, number, _| number }.map(&:last) }
    end

    # Participants seated in a single-elimination pod, or advanced through a cut round without one (a bye).
    def cut_ids(participations)
      cut = { rounds: { type: "SingleEliminationRound" } }
      seated = Seating.joins(pod: :round).where(cut).select(:event_participant_id)
      advanced = Advance.current.joins(:round).where(cut).select(:event_participant_id)
      EventParticipant.where(id: participations.map(&:id))
        .where(id: seated).or(EventParticipant.where(id: advanced)).pluck(:id).to_set
    end

    # { event id => cut size } for tournaments, as Tournament#top_cut_size_or_suggested: a cut left unset is
    # the suggestion for the enrolled players, counted for all those events in one query.
    def cut_sizes(participations)
      tournaments = participations.map(&:event).grep(Tournament)
      enrolled = enrolled_counts(tournaments.select { |event| event.top_cut_size.nil? })
      tournaments.to_h { |event| [event.id, event.top_cut_size || suggested_cut(event, enrolled)] }
    end

    def suggested_cut(event, enrolled)
      Tournaments::Structure.suggested(enrolled.fetch(event.id, 0), format: event.format)[:top_cut_size]
    end

    def enrolled_counts(events)
      events.empty? ? {} : EventParticipant.enrolled.where(event_id: events.map(&:id)).group(:event_id).count
    end

    # { seat => times } from the round seats; nil for 1v1 (no seats shown).
    def seats_of(participation, round_seats)
      return if participation.event.one_v_one?

      EventParticipant.empty_seat_counts.merge(round_seats.fetch(participation.id, []).tally)
    end

    # Same text as EventsHelper#event_format_label.
    def format_line(event)
      return I18n.t("play.header.multiplayer") unless event.one_v_one?

      I18n.t("play.events.format_badge", game_format: I18n.t("play.formats.#{event.play}"),
                                         games: event.match_games)
    end

    def row(participation, context)
      event = participation.event
      Row.new(event: event, position: participation.final_position, participants: context[:sizes].fetch(event.id, 0),
              **record(participation), **decklist(participation), **cut(participation, context),
              **seat_fields(participation, context), **event_fields(event))
    end

    def seat_fields(participation, context)
      { seats: seats_of(participation, context[:round_seats]),
        round_seats: (context[:round_seats].fetch(participation.id, []) unless participation.event.one_v_one?) }
    end

    def event_fields(event)
      { organizer_name: event.event_organizer.user&.name.to_s, format_line: format_line(event),
        season: event.circuit&.name }
    end

    def record(participation)
      wins = participation.number_of_wins
      losses = participation.number_of_losses
      draws = participation.number_of_draws
      { wins: wins, losses: losses, draws: draws, games: wins + losses + draws }
    end

    def decklist(participation)
      event = participation.event
      visible = event.show_decklists && event.finished? && participation.decklist.present?
      { decklist_visible: visible, decklist: (participation.decklist if visible),
        commander: participation.commander_text }
    end

    def cut(participation, context)
      { made_cut: context[:cut_ids].include?(participation.id),
        cut_size: context[:cut_sizes][participation.event_id]&.nonzero? }
    end
  end
end
