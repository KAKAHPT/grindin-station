# frozen_string_literal: true

module Organizer
  class EventParticipantsController < OrganizerController # rubocop:disable Metrics/ClassLength
    layout "modal"
    DESK_ACTIONS = %i[update check_in undo_check_in check_in_all mark_paid mark_unpaid].freeze
    STATUSES = %w[enrolled checked_in waitlisted dropped].freeze
    # Roster filters on what the desk still has to do; each lists enrolled players only.
    DESK_FILTERS = {
      "not_checked_in" => ->(p) { !p.checked_in? },
      "no_decklist" => ->(p) { p.decklist.blank? },
      "unpaid" => ->(p) { !p.paid? }
    }.freeze

    allow_roles :organizer, :judge, :scorekeeper, :caster, only: :index
    allow_roles :organizer, :judge, :scorekeeper, only: DESK_ACTIONS
    allow_roles :organizer, :judge, except: [:index, *DESK_ACTIONS]

    # The Add player lookup is for an organizer typing, not for listing accounts.
    rate_limit to: 60, within: 1.minute, only: :search, by: -> { current_user.id },
               with: -> { render json: [], status: :too_many_requests }

    SCOREKEEPER_ATTRIBUTES = %w[checked_in paid].freeze
    ADD_MODES = %w[email name manual list].freeze
    # The "Several" tab: guests pasted one name per line.
    LIST_LIMIT = 200

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
      @mode = "email"
    end

    # The Add player dialog's lookup (JSON): accounts by name or e-mail, flagged when already in the event.
    def search
      rows = Registrations::PlayerSearch.new(load_tournament, mode: params[:mode], text: params[:q]).call
      render json: rows
    end

    def create
      @event_participant = EventParticipant.new(event: load_tournament)
      @mode = params[:mode].presence_in(ADD_MODES) || "email"
      if @event_participant.event.points_locked?
        return redirect_to roster_path(@event_participant.event), alert: t("flash.alert.registration_closed")
      end

      return create_list if @mode == "list"

      @event_participant.attributes = event_participant_params

      if picked_by_name? && @event_participant.save
        redirect_to [:organizer, @event_participant.event, :event_participants, { layout: "application" }],
                    notice: "#{@event_participant.name} added!"
      else
        render :new, status: :unprocessable_entity, layout: modal_layout
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

    # Everyone enrolled who is not checked in yet, in one go.
    def check_in_all
      @event = load_tournament
      pending = @event.event_participants.enrolled.where(checked_in: false).to_a
      pending.each { |participant| participant.update!(checked_in: true) }
      redirect_to roster_path(@event), notice: t("flash.notice.checked_in_all", count: pending.size)
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

    # Adds one guest per pasted line, all or none: a refused name comes back in the dialog with its reason.
    def create_list
      event = @event_participant.event
      @names = params[:names].to_s
      names = @names.lines.map(&:squish).compact_blank.uniq
      refused = list_refusal(event, names) || add_guests(event, names)
      return redirect_to(roster_path(event), notice: t("flash.notice.players_added", count: names.size)) unless refused

      @event_participant.errors.add(:base, refused)
      render :new, status: :unprocessable_entity, layout: modal_layout
    end

    def list_refusal(_event, names)
      return t("organizer.roster.add.list_empty") if names.empty?

      t("organizer.roster.add.list_too_long", limit: LIST_LIMIT) if names.size > LIST_LIMIT
    end

    # nil when every guest was saved; otherwise nothing is saved and the first refusal is returned.
    def add_guests(event, names)
      terms = event_participant_params[:accepted_terms]
      refused = nil
      # One name check per guest (EventParticipant#guest_name_free) is the work, not an N+1.
      Prosopite.pause
      EventParticipant.transaction do
        names.each do |name|
          guest = EventParticipant.new(event: event, player_name: name, accepted_terms: terms)
          next if guest.save

          refused = "#{name}: #{guest.errors.full_messages.to_sentence}"
          raise ActiveRecord::Rollback
        end
      end
      refused
    ensure
      Prosopite.resume
    end

    # The "by name" tab adds only a player picked from the list; a typed name alone would be a guest.
    def picked_by_name?
      return true unless @mode == "name" && @event_participant.player_id.blank?

      @event_participant.errors.add(:base, t("organizer.roster.add.pick_one"))
      false
    end

    def desk_update(attributes)
      @event = load_tournament
      participant = load_event_participant(@event)
      participant.update!(attributes)
      redirect_to roster_path(@event), notice: t("flash.notice.update_successful")
    end

    # Back to the roster as the organizer was reading it: the same filter, search and page.
    def roster_path(event)
      [:organizer, event, :event_participants, { layout: "application", **roster_view }]
    end

    def roster_view
      query = URI.parse(request.referer.to_s).query
      Rack::Utils.parse_query(query).slice("status", "query", "page").compact_blank.symbolize_keys
    rescue URI::InvalidURIError
      {}
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
      desk = DESK_FILTERS[params[:status]]
      return participants.select { |p| p.enrolled? && desk.call(p) } if desk
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
                      player_id
                      player_email
                      player_name
                      decklist
                      accepted_terms
                    ])
    end
  end
end
