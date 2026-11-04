# frozen_string_literal: true

module Organizer
  class TournamentsController < OrganizerController
    public_actions :index
    require_organizer only: %i[new create]
    allow_roles :organizer, only: %i[edit update]
    allow_roles :organizer, :judge, :scorekeeper, only: :show
    # New and Settings are full pages (the tournament page's Settings tab), never the modal.
    layout "application"

    PAST_STATES = %i[finished canceled].freeze

    # Active (not finished/canceled) or, with ?past=1, past tournaments as cards.
    def index
      @past = params[:past].present?
      scope = Tournament.with_attached_cover.staffed_by(current_user).preload(:rounds)
      @tournaments =
        if @past then scope.where(state: PAST_STATES).order(start_time: :desc)
        else scope.where.not(state: PAST_STATES).order(:start_time)
        end
      @editable_ids = editable_ids(@tournaments)
    end

    def show
      @tournament =
        Tournament
          .staffed_by(current_user)
          .with_attached_cover
          .preload(
            rounds: :pods,
            event_participants: { player: :user }
          ).find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to url_for(action: :index), alert: t("flash.alert.not_authorized_tournament")
    end

    def new
      @tournament = Tournament.new
    end

    def edit
      @tournament = Tournament.staffed_by(current_user).with_attached_cover.find params[:id]
    end

    def create
      @tournament = Tournament.new(tournament_params.merge(event_organizer: current_organizer))

      if @tournament.save
        redirect_to [:organizer, @tournament], notice: t("flash.notice.tournament_created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      @tournament = Tournament.staffed_by(current_user).with_attached_cover.find params[:id]
      # The format is chosen at creation only (the model refuses a change too).
      @tournament.attributes = tournament_params.except(:format)

      if @tournament.save
        if @tournament.state_previously_changed? && @tournament.single_elimination?
          redirect_to [:organizer, @tournament, @tournament.rounds.max_by(&:number).becomes(Round)],
                      notice: t("flash.notice.tournament_advanced")
        else
          redirect_to [:organizer, @tournament], notice: t("flash.notice.tournament_updated")
        end
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    # Tournaments the user may edit: owned, or staffed as an organizer (one query for the staff roles).
    def editable_ids(tournaments)
      organizer_id = current_organizer&.id
      staffed = EventStaff.where(user: current_user, role: "organizer", event_id: tournaments.map(&:id)).pluck(:event_id)
      tournaments.select { |t| organizer_id && t.event_organizer_id == organizer_id }.map(&:id) + staffed
    end

    def tournament_params
      params.expect(tournament: %i[
                      name
                      state
                      description
                      start_time
                      end_time
                      minimum_participants
                      maximum_participants
                      prizes
                      address
                      schedule
                      rules
                      price
                      currency
                      cover
                      format
                      match_games
                      points_win
                      points_draw
                      points_loss
                      points_bye
                      swiss_rounds_count
                      top_cut_size
                      round_minutes
                      top_cut_round_minutes
                      self_report_enabled
                      result_confirmation
                      confirmation_timeout_minutes
                      waitlist_enabled
                      show_commanders_in_standings
                      show_decklists
                      top_cut_timeout_rule
                    ])
    end
  end
end
