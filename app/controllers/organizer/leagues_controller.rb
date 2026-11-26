# frozen_string_literal: true

module Organizer
  class LeaguesController < OrganizerController # rubocop:disable Metrics/ClassLength -- the league and its desk
    require_organizer

    def index
      @leagues = League
        .with_attached_cover
        .where.not(state: :canceled)
        .for_organizer(current_organizer)
        .preload(:rounds)
    end

    def show
      @league = League.for_organizer(current_organizer).preload(
        rounds: :pods,
        event_participants: { player: :user }
      ).find(params[:id])
      @tab = params[:tab].presence_in(%w[players feed standings details edit]) || "tables"
      load_tab if @league.play_mode_open_tables?
    rescue ActiveRecord::RecordNotFound
      redirect_to [:organizer, :leagues], alert: t("flash.alert.not_authorized_league")
    end

    def new
      @league = League.new
    end

    def edit
      @league = League.for_organizer(current_organizer).find params[:id]
    end

    def create
      @league = League.create!(
        league_params.merge(event_organizer: current_organizer)
      )

      redirect_to [:organizer, @league], notice: t("flash.notice.league_created")
    rescue ActiveRecord::RecordInvalid => e
      @league = League.new(league_params.merge(event_organizer: current_organizer))
      @league.errors.add(:base, e.message)
      render :new, status: :unprocessable_entity
    end

    def update
      @league = League.for_organizer(current_organizer).find(params[:id])
      @league.attributes = league_params

      if @league.save
        audit_update

        redirect_to [:organizer, @league], notice: t("flash.notice.league_updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    SCORING = %i[play_mode starting_points wager_percentage draw_rule].freeze
    STEPS = { "play" => :start, "closing" => :close, "reopen" => :reopen, "finals" => :make_cut,
              "finished" => :finish }.freeze

    # The league's steps: start, close, reopen, make the cut, finish (Leagues::Lifecycle).
    def transition # rubocop:disable Metrics/AbcSize
      @league = League.for_organizer(current_organizer).find(params[:id])
      step = STEPS.fetch(params[:to].to_s) { raise Leagues::Lifecycle::NotAllowed, "unknown" }
      Leagues::Lifecycle.public_send(step, @league, by: current_user)
      Turbo::StreamsChannel.broadcast_refresh_later_to(@league, :tables)
      # "Make cut" with nobody qualified finishes the league by the standings.
      done = @league.finished? ? "finished" : params[:to]
      redirect_to [:organizer, @league], notice: t("league_desk.n_#{done}")
    rescue Leagues::Lifecycle::NotAllowed
      redirect_to [:organizer, @league], alert: t("league_desk.e_transition")
    end

    # Approves or refuses a table's cancellation request.
    def decide_cancel # rubocop:disable Metrics/AbcSize
      @league = League.for_organizer(current_organizer).find(params[:id])
      table = @league.league_tables.find(params[:table_id])
      approve = params[:approve] == "1"
      Leagues::Tables::DecideCancel.call(table: table, by: current_user, approve: approve)
      Turbo::StreamsChannel.broadcast_refresh_later_to(@league, :tables)
      redirect_to [:organizer, @league], notice: t("league_desk.n_#{approve ? 'approved' : 'refused'}")
    rescue Leagues::Tables::NotAllowed
      redirect_to [:organizer, @league], alert: t("league_desk.e_transition")
    end

    # The organizer cancels a full table still to finish, with a reason: the game counts for nothing.
    def cancel_table # rubocop:disable Metrics/AbcSize
      @league = League.for_organizer(current_organizer).find(params[:id])
      table = @league.league_tables.find(params[:table_id])
      Leagues::Tables::DecideCancel.void(table: table, by: current_user, reason: params[:reason])
      Turbo::StreamsChannel.broadcast_refresh_later_to(@league, :tables)
      redirect_to [:organizer, @league], notice: t("league_desk.n_approved")
    rescue Leagues::Tables::NotAllowed => e
      redirect_to [:organizer, @league], alert: t("leagues.tables.not_allowed.#{e.message}")
    end

    # The organizer takes a player out of the league (Leagues::Leave).
    def drop_participant # rubocop:disable Metrics/AbcSize
      @league = League.for_organizer(current_organizer).find(params[:id])
      participant = @league.event_participants.where(dropped: false).find(params[:participant_id])
      Leagues::Leave.call(league: @league, participant: participant, by: current_user)
      Turbo::StreamsChannel.broadcast_refresh_later_to(@league, :tables)
      redirect_to organizer_league_path(@league, tab: "players"),
                  notice: t("league_desk.n_dropped", name: participant.name)
    rescue Leagues::Tables::NotAllowed => e
      redirect_to [:organizer, @league], alert: t("leagues.tables.not_allowed.#{e.message}")
    end

    # A player who left (or was taken out) asks the organization to come back: the organizer readmits them, with the
    # points and games they had. Not once the cut is made.
    def readmit_participant # rubocop:disable Metrics/AbcSize
      @league = League.for_organizer(current_organizer).find(params[:id])
      participant = @league.event_participants.where(dropped: true).find(params[:participant_id])
      over = @league.finals? || @league.finished?
      return redirect_to [:organizer, @league], alert: t("league_desk.e_transition") if over

      participant.update!(dropped: false, drop_reason: nil)
      Audit.record(:participant_readmitted, actor: current_user, subject: participant, event: @league,
                                            participant_id: participant.id)
      Turbo::StreamsChannel.broadcast_refresh_later_to(@league, :tables)
      redirect_to organizer_league_path(@league, tab: "players"),
                  notice: t("league_desk.n_readmitted", name: participant.name)
    end

    GAME_STATES = %w[play closing closed].freeze

    # The organizer enters (or corrects) the result of a league game or of a cut table: params[:result] is the
    # winner's participant id or "draw". A league game only until the cut is made (it would change who made
    # it); a cut table only while its round is open.
    def enter_result # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
      @league = League.for_organizer(current_organizer).find(params[:id])
      pod = Pod.joins(:round).where(rounds: { event_id: @league.id }).find(params[:pod_id])
      cut = pod.round.is_a?(LeagueCutRound)
      open = cut ? @league.finals? && pod.round.finished_at.nil? : @league.state.in?(GAME_STATES)
      return redirect_to [:organizer, @league], alert: t("league_desk.e_transition") unless open

      winner = pod.event_participants.find_by(id: params[:result]) unless params[:result] == "draw"
      if winner.nil? && params[:result] != "draw"
        return redirect_to [:organizer, @league], alert: t("leagues.tables.not_allowed.invalid_result")
      end

      Results::Apply.call(pod: pod, type: winner ? "Win" : "Draw", winner: winner, by: current_user)
      pod.clear_report_state!
      Turbo::StreamsChannel.broadcast_refresh_later_to(@league, :tables)
      # A result changed from the Feed tab comes back to it.
      redirect_to organizer_league_path(@league, tab: params[:tab].presence_in(%w[feed])),
                  notice: t("league_desk.n_result")
    rescue Results::NotAllowed => e
      redirect_to [:organizer, @league], alert: t("results.not_allowed.#{e.message}")
    end

    # Answers a correction request: params[:result] is the winner's participant id, "draw" or "keep".
    def decide_correction # rubocop:disable Metrics/AbcSize
      @league = League.for_organizer(current_organizer).find(params[:id])
      table = @league.league_tables.find(params[:table_id])
      Leagues::Tables::ResolveCorrection.call(table: table, by: current_user, result: params[:result])
      Turbo::StreamsChannel.broadcast_refresh_later_to(@league, :tables)
      redirect_to [:organizer, @league], notice: t("league_desk.n_correction_#{table.correction_state}")
    rescue Leagues::Tables::NotAllowed
      redirect_to [:organizer, @league], alert: t("league_desk.e_transition")
    end

    # Every table of the cut round has its winner: the round is closed and the next one (or the end) follows.
    def close_cut_round # rubocop:disable Metrics/AbcSize
      @league = League.for_organizer(current_organizer).find(params[:id])
      round = @league.rounds.where(type: "LeagueCutRound", finished_at: nil).find(params[:round_id])
      return redirect_to [:organizer, @league], alert: t("league_desk.e_transition") unless round.finished?

      round.update!(finished_at: Time.current)
      redirect_to [:organizer, @league], notice: t("league_desk.n_round_closed")
    end

    def create_pickup_pod
      @league = League.for_organizer(current_organizer).find(params[:id])
      Leagues::CreatePickupPodJob.perform_now(@league)
      redirect_to [:organizer, @league], notice: t("flash.notice.pickup_pod_created")
    rescue ActiveRecord::RecordNotFound
      redirect_to [:organizer, :leagues], alert: t("flash.alert.not_authorized_league")
    end

    private

    # A step taken from the form, and a new end date (the league extended or shortened).
    def audit_update
      if @league.state_previously_changed?
        from, to = @league.state_previous_change
        Audit.record(:event_state_changed, subject: @league, event: @league, from: from, to: to)
      end
      return unless @league.end_time_previously_changed? && @league.playing?

      from, to = @league.end_time_previous_change
      Audit.record(:league_end_changed, actor: current_user, subject: @league, event: @league,
                                        from: from&.iso8601, to: to&.iso8601)
    end

    # The organizer's view of an open-tables league: the full tables still to finish (with any cancellation
    # asked) and, once closed, who qualifies for the cut.
    def load_desk
      @pending_tables = @league.league_tables.filled
        .preload(:cancel_requested_by, pod: [{ round: :results },
                                             { seatings: { event_participant: { player: :user } } }])
        .order(:filled_at).select(&:in_play?)
      @corrections = @league.league_tables.correction_pending
        .preload(:correction_requested_by, pod: [{ round: :results },
                                                 { seatings: { event_participant: { player: :user } } }])
        .order(:correction_requested_at).to_a
      @cut_field = @league.cut_field if @league.closed?
      @cut_round = LeagueCutRound.where(event: @league).order(:number)
        .preload(:results, pods: { seatings: { event_participant: { player: :user } } }).last
    end

    # What the open tab of an open-tables league needs, on top of the desk's own lists.
    def load_tab
      load_desk
      load_feed if @tab == "feed"
      load_standings if @tab == "standings"
    end

    # The Feed tab: the league's finished games, latest first, 15 a page; each can be opened and changed.
    def load_feed
      @feed = @league.league_tables.filled.joins(pod: :round).where.not(rounds: { finished_at: nil })
        .order("rounds.finished_at DESC")
        .preload(pod: [{ round: :results }, { seatings: { event_participant: { player: :user } } }])
        .page(params[:page]).per(15)
    end

    # The Standings tab: the same table the players see, 16 places a page.
    def load_standings
      @standings = Kaminari.paginate_array(@league.standings_order).page(params[:page])
        .per(::LeaguesController::STANDINGS_PER_PAGE)
    end

    def league_params
      params.expect(
        league: %i[
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
          wager_percentage
          play_mode
          circuit_id
          cover
          starting_points
          draw_rule
          top_cut_size
          min_games_for_cut
          max_games_per_week
          max_games_vs_same_opponent
          round_minutes
          result_confirmation
        ]
      ).except(*locked_params)
    end

    # State changes go through #transition; the scoring is fixed once games count.
    def locked_params
      league = @league
      return [:state] unless league&.persisted?
      return [] unless league.play_mode_open_tables?

      league.playing? || league.finished? ? [:state, *SCORING, :top_cut_size] : [:state]
    end
  end
end
