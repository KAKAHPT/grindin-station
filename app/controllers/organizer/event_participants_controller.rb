# frozen_string_literal: true

module Organizer
  class EventParticipantsController < OrganizerController # rubocop:disable Metrics/ClassLength
    layout "modal"
    DESK_ACTIONS = %i[update check_in undo_check_in mark_paid mark_unpaid].freeze
    STATUSES = %w[enrolled checked_in waitlisted dropped].freeze

    allow_roles :organizer, :judge, :scorekeeper, :caster, only: :index
    allow_roles :organizer, :scorekeeper, only: DESK_ACTIONS
    allow_roles :organizer, except: [:index, *DESK_ACTIONS]

    SCOREKEEPER_ATTRIBUTES = %w[checked_in paid].freeze

    def index
      @event = load_tournament

      case @event.state
      when "registration_open", "registration_closed"
        @event_participants = roster_participants(@event).sort_by(&:name)
      else
        @event_participants = ranked_participants(@event)
      end

      @roster_counts = roster_counts(@event)
      @event_participants = filter_by_status(@event_participants)

      if params[:query].present?
        @event_participants =
          @event_participants.select do |p|
            p.name.downcase.include?(params[:query].downcase)
          end
      end

      @layout_mode = "modal"
      return unless params[:layout] == "application"

      @layout_mode = "application"
      render layout: "application"
    end

    def new
      @event_participant = EventParticipant.new(event: load_tournament)
    end

    def create
      @event_participant = EventParticipant.new(event: load_tournament)
      if @event_participant.event.points_locked?
        return redirect_to roster_path(@event_participant.event), alert: t("flash.alert.registration_closed")
      end

      @event_participant.attributes = event_participant_params

      if @event_participant.save
        redirect_to [:organizer, @event_participant.event, :event_participants, { layout: "application" }],
                    notice: "#{@event_participant.name} added!"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      @event = load_tournament
      @event_participant = load_event_participant(@event)

      @event_participant.update(update_params)
      # TODO: stay in place or fix the updated item
      redirect_to [:organizer, @event, :event_participants, { layout: "application" }],
                  notice: "#{@event_participant.name} #{@event_participant.dropped? ? 'dropped' : 'updated'}!"
    end

    def check_in = desk_update(checked_in: true)
    def undo_check_in = desk_update(checked_in: false)
    def mark_paid = desk_update(paid: true)
    def mark_unpaid = desk_update(paid: false)

    def drop
      @event = load_tournament
      participant = load_event_participant(@event)
      Registrations::Drop.call(participant: participant, by: current_user,
                               reason: params[:reason] == "no_show" ? "no_show" : "drop")
      redirect_to roster_path(@event), notice: t("flash.notice.participant_dropped", name: participant.name)
    end

    def promote
      @event = load_tournament
      participant = load_event_participant(@event)
      return redirect_to roster_path(@event), alert: t("flash.alert.registration_closed") if @event.points_locked?

      @event.promote_from_waitlist!(participant)
      redirect_to roster_path(@event), notice: t("flash.notice.participant_promoted", name: participant.name)
    end

    def destroy; end

    private

    def desk_update(attributes)
      @event = load_tournament
      participant = load_event_participant(@event)
      participant.update!(attributes)
      redirect_to roster_path(@event), notice: t("flash.notice.update_successful")
    end

    def roster_path(event)
      [:organizer, event, :event_participants, { layout: "application" }]
    end

    # Every participant with what the roster rows read (standings, infractions) preloaded.
    def roster_participants(event)
      participants = EventParticipant.standings_for(event)
      ActiveRecord::Associations::Preloader.new(records: participants, associations: { player: :infractions }).call
      participants
    end

    # The standings with a rank each (the public order, Feeds::Standings.ranked); the waitlist is not
    # ranked and follows in waitlist order.
    def ranked_participants(event)
      participants = roster_participants(event)
      ranked = Feeds::Standings.ranked(event, participants)
      ranked.each.with_index(1) { |p, rank| p.rank = rank }
      ranked + participants.select(&:waitlisted?).sort_by { |p| p.waitlist_position.to_i }
    end

    def roster_counts(event)
      participants = event.event_participants.to_a
      STATUSES.index_with { |status| participants.count { |p| p.roster_status?(status) } }.symbolize_keys
    end

    def filter_by_status(participants)
      return participants unless STATUSES.include?(params[:status])

      participants.select { |p| p.roster_status?(params[:status]) }
    end

    def load_tournament
      Tournament.staffed_by(current_user).with_attached_cover.find params[:tournament_id]
    end

    def load_event_participant(tournament)
      tournament.event_participants.find(params[:id])
    end

    # Scorekeepers only check players in and mark them paid.
    def update_params
      staff_role == "scorekeeper" ? event_participant_params.slice(*SCOREKEEPER_ATTRIBUTES) : event_participant_params
    end

    def event_participant_params
      params.expect(event_participant: %i[
                      dropped
                      checked_in
                      paid
                      player_email
                      player_name
                      decklist
                      accepted_terms
                    ])
    end
  end
end
