# frozen_string_literal: true

module Organizer
  class RoundsController < OrganizerController
    allow_roles :organizer, :judge, :scorekeeper, only: %i[show print slips]
    allow_roles :organizer, except: %i[show print slips]

    layout "print", only: %i[print slips]

    def show
      event = load_tournament
      @round = load_round(event)
      load_pairings
    end

    def print
      load_printable
    end

    def slips
      load_printable
    end

    def update
      event = load_tournament
      @round = load_round(event)

      case round_params[:action]
      when "publish"
        @round.update(published: true)
        redirect_to [:organizer, @round.event, @round.becomes(Round)], notice: t("flash.notice.round_published")
      when "start"
        @round.update(started_at: Time.zone.now)
        redirect_to [:organizer, @round.event, @round.becomes(Round)], notice: t("flash.notice.round_started")
      when "close"
        close_round(event)
      else
        head :unprocessable_content
      end
    end

    # Round 1 cannot be undone: the state machine has no way back from swiss to registration_closed.
    def destroy
      event = load_tournament
      round = load_round(event)
      if round.number != event.rounds.maximum(:number)
        return redirect_to [:organizer, event, round.becomes(Round)], alert: t("rounds.cannot_undo_older")
      end
      if round.number == 1
        return redirect_to [:organizer, event, round.becomes(Round)], alert: t("rounds.cannot_undo_first")
      end

      Round.transaction { roll_back(event, round) }
      redirect_to [:organizer, event, event.rounds.max_by(&:number).becomes(Round)],
                  notice: t("flash.notice.round_rollback")
    end

    private

    def roll_back(event, round)
      ActiveRecord::Associations::Preloader.new(records: [round], associations: { pods: :seatings }).call
      round.destroy!
      reopened = event.rounds.reload.max_by(&:number)
      reopened.update!(finished_at: nil)
      ::Standings::Snapshot.discard(event, reopened.number)
      return unless event.single_elimination? && event.rounds.none?(SingleEliminationRound)

      # The one step back the state machine allows: undoing the first cut round. No state side effects apply.
      event.update_columns(state: Tournament.states[:swiss], updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end

    def load_printable
      @event = load_tournament
      @round = load_round(@event)
      @pods = @round.pods.order(:number).preload(seatings: { event_participant: { player: :user } })
    end

    def load_pairings
      @pods = load_pods(@round)
    end

    # Closing sets finished_at, which advances a swiss round to the next (unpublished) one.
    def close_round(event)
      unless @round.closable?
        flash.now[:alert] = t("rounds.cannot_close", tables: @round.blocking_pods.map(&:number).join(", "))
        load_pairings
        return render :show, status: :unprocessable_content
      end

      @round.update(finished_at: Time.zone.now)
      latest = event.rounds.reload.max_by(&:number)
      notice = latest == @round ? t("rounds.closed") : t("rounds.next_round_created")
      redirect_to [:organizer, event, latest.becomes(Round)], notice: notice
    end

    def round_params
      params.expect(round: [:action])
    end

    def load_tournament
      Tournament.staffed_by(current_user).with_attached_cover.find params[:tournament_id]
    end

    def load_round(tournament)
      tournament.rounds.find params[:id]
    end

    def load_pods(round)
      round.pods.preload(:event, :judge_calls, { round: :results }, seatings: { event_participant: { player: :user } },
                                                                    event_participants: { player: :user })
    end
  end
end
