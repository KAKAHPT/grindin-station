# frozen_string_literal: true

module Organizer
  class TournamentsController < OrganizerController # rubocop:disable Metrics/ClassLength -- the permitted list
    public_actions :index
    require_organizer only: %i[new create]
    allow_roles :organizer, only: %i[edit update reopen]
    allow_roles :organizer, :judge, :scorekeeper, only: :show
    # New and Settings are full pages (the tournament page's Settings tab), never the modal.
    layout "application"

    PAST_STATES = %i[finished canceled].freeze

    # Active (not finished/canceled) or, with ?past=1, past tournaments as cards.
    def index
      @past = params[:past].present?
      scope = Tournament.with_attached_cover.staffed_by(current_user)
      @tournaments =
        if @past then scope.where(state: PAST_STATES).order(start_time: :desc)
        else scope.where.not(state: PAST_STATES).order(:start_time)
        end
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
      attributes = tournament_params.merge(event_organizer: current_organizer)
      # The form has one Format select: Commander / cEDH is the pods, any other game format is 1v1.
      if attributes[:game_format].present? && attributes[:format].blank?
        attributes[:format] = attributes[:game_format] == "commander" ? "multiplayer" : "one_v_one"
      end
      @tournament = Tournament.new(attributes)

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
        audit_settings(@tournament)
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

    # A finished tournament goes back to its last round so a result can be corrected; closing it again finishes.
    def reopen
      @tournament = Tournament.staffed_by(current_user).find params[:id]
      last = @tournament.rounds.max_by(&:number)
      unless @tournament.finished? && last
        return redirect_to [:organizer, @tournament], alert: t("flash.alert.not_allowed")
      end

      state = last.is_a?(SingleEliminationRound) ? :single_elimination : :swiss
      Tournament.transaction do
        # Finished allows no transition back: the one step the undo of a round also takes, with no state side effects.
        @tournament.update_columns(state: Tournament.states[state], updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        @tournament.event_participants.update_all(final_position: nil) # rubocop:disable Rails/SkipsModelValidations
        last.update!(finished_at: nil)
        ::Standings::Snapshot.discard(@tournament, last.number) if last.is_a?(SwissRound)
      end
      Audit.record(:event_state_changed, subject: @tournament, event: @tournament, from: "finished", to: state.to_s)
      Rankings::RebuildJob.schedule!
      redirect_to [:organizer, @tournament, last.becomes(Round)], notice: t("flash.notice.tournament_reopened")
    end

    private

    def audit_settings(tournament)
      if tournament.state_previously_changed?
        from, to = tournament.state_previous_change
        Audit.record(:event_state_changed, subject: tournament, event: tournament, from: from, to: to)
      end
      return unless tournament.saved_change_to_featured?

      Audit.record(:featured_changed, subject: tournament, event: tournament, featured: tournament.featured)
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
                      country
                      schedule
                      rules
                      price
                      currency
                      cover
                      format
                      match_games
                      game_format
                      points_win
                      points_draw
                      points_loss
                      points_bye
                      swiss_rounds_count
                      top_cut_size
                      round_minutes
                      top_cut_round_minutes
                      pairing_mode
                      uneven_field
                      self_report_enabled
                      result_confirmation
                      confirmation_timeout_minutes
                      waitlist_enabled
                      decklist_required
                      self_check_in_enabled
                      check_in_opens_hours_before
                      show_commanders_in_standings
                      show_decklists
                      show_beaten_in_standings
                      show_unique_in_standings
                      hide_standings_until_finished
                      top_cut_timeout_rule
                      featured
                    ])
    end
  end
end
