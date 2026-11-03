# frozen_string_literal: true

module Organizer
  class TournamentsController < OrganizerController
    public_actions :index
    require_organizer only: %i[new create]
    allow_roles :organizer, only: %i[edit update]
    allow_roles :organizer, :judge, :scorekeeper, only: :show

    def index
      @tournaments = Tournament.with_attached_cover.where.not(state: :canceled).staffed_by(current_user).preload(:rounds)
    end

    def show
      @tournament =
        Tournament
          .staffed_by(current_user)
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
      @tournament = Tournament.staffed_by(current_user).find params[:id]
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
      @tournament = Tournament.staffed_by(current_user).find params[:id]
      @tournament.attributes = tournament_params

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
