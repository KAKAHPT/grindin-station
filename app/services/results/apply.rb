# frozen_string_literal: true

module Results
  # Records a pod's result. While the round is open the rows are updated in place; once it is
  # closed (finished_at) they are never overwritten: fresh rows are written and the old ones
  # point at them through superseded_by, so only Result.current feeds scoring.
  #
  # 1v1 events also take the game score: games: { winner: [won, lost, drawn] } for a Win/Advance
  # (the loser gets the mirror) or { games: [won, lost, drawn] } for a Draw (both players). It is
  # required there (except for a Penalty) and checked against the event's match_games; UNSCORED
  # (an Advance by time called in the cut) writes 0-0-0. Multiplayer callers pass no games.
  class Apply # rubocop:disable Metrics/ClassLength -- the 1v1 score checks live with the writes
    Outcome = Data.define(:results, :warning)

    UNSCORED = :unscored
    # Bo3 stopped on time at 1-0: 1-0-1 (the unfinished game is a draw, MTR) or 1-0-0.
    WINNER_SCORES = { 3 => [[2, 0, 0], [2, 1, 0], [1, 0, 1], [1, 0, 0]], 1 => [[1, 0, 0]] }.freeze
    DRAW_SCORES = { 3 => [[1, 1, 1], [1, 1, 0], [0, 0, 1]], 1 => [[0, 0, 1]] }.freeze
    UNSCORED_TYPES = %w[Penalty Eliminated].freeze

    def self.call(pod:, type:, winner: nil, by: nil, games: nil)
      new(pod: pod, type: type, winner: winner, by: by, games: games).call
    end

    # The games keyword from a "won-lost-drawn" form value ("2-1-0"), nil when blank.
    def self.games_param(type, value)
      return if value.blank?

      { (type == "Draw" ? :games : :winner) => value.to_s.split("-") }
    end

    # Raises NotAllowed unless the games are a possible score for this result at a 1v1 event.
    def self.check_games!(event, type, games)
      return if !event.one_v_one? || unscored?(type, games)
      raise NotAllowed, "score_required" if games.blank?

      triple = triple_for(type, games)
      raise NotAllowed, "impossible_score" unless allowed_scores(event, type).include?(triple)

      triple
    end

    # A Penalty/Eliminated, or an Advance by time called (UNSCORED), carries no score.
    def self.unscored?(type, games)
      type.in?(UNSCORED_TYPES) || (games == UNSCORED && type == "Advance")
    end
    private_class_method :unscored?

    def self.triple_for(type, games)
      return unless games.respond_to?(:to_h)

      normalize(games.to_h.with_indifferent_access[type == "Draw" ? :games : :winner])
    end
    private_class_method :triple_for

    def self.allowed_scores(event, type)
      (type == "Draw" ? DRAW_SCORES : WINNER_SCORES).fetch(event.match_games, [])
    end
    private_class_method :allowed_scores

    def self.normalize(list)
      Array(list).map { |value| value.to_s.match?(/\A\d+\z/) ? value.to_i : nil }
    end
    private_class_method :normalize

    # :later_round_published when a round after the pod's is already out, else nil.
    def self.warning_for(pod)
      round = pod.round
      :later_round_published if round.event.rounds.where("number > ?", round.number).exists?(published: true)
    end

    # The top cut has no wins or draws: a win there is an Advance (the others are eliminated), a draw is refused.
    def self.type_for(round, type)
      return type unless round.is_a?(SingleEliminationRound)
      raise NotAllowed, "draw_in_top_cut" if type == "Draw"

      type == "Win" ? "Advance" : type
    end

    def initialize(pod:, type:, winner:, by:, games: nil)
      @pod = pod
      @round = pod.round
      @type = self.class.type_for(@round, type)
      @winner = winner
      @by = by
      @score = self.class.check_games!(@round.event, @type, games)
    end

    def call
      closed = false
      results =
        Result.transaction do
          closed = Round.finished.exists?(@round.id) # fresh: the round may have closed since it was loaded
          assignments.map { |participant, type| closed ? supersede(participant, type) : update(participant, type) }
        end
      audit_correction if closed
      ::Standings::Snapshot.refresh(@round)
      Outcome.new(results: results, warning: self.class.warning_for(@pod))
    end

    private

    # A closed round's result rewritten: who, which pod and what it became ("Win: <winner>").
    def audit_correction
      Audit.record(:result_corrected, actor: @by, subject: @pod, event: @round.event, pod_id: @pod.id,
                                      round_number: @round.number, result: [@type, @winner&.name].compact.join(": "))
    end

    # { participant => result type } for the touched seats. A Penalty already on a seat stays.
    def assignments
      raise "Must select a winner" if @type.in?(%w[Win Advance]) && @winner.blank?

      case @type
      when "Advance" then others.index_with("Eliminated").merge(@winner => "Advance")
      when "Win" then others.index_with { |p| keep_penalty(p, "Loss") }.merge(@winner => "Win")
      when "Draw" then @pod.event_participants.index_with { |p| keep_penalty(p, "Draw") }
      when "Penalty" then { @winner => "Penalty" }
      else {}
      end
    end

    def others
      @pod.event_participants.reject { |p| p == @winner }
    end

    def keep_penalty(participant, type)
      current_for(participant)&.type == "Penalty" ? "Penalty" : type
    end

    # The seated players' current results come in one query; anyone else (a penalty) is looked up alone.
    def current_for(participant)
      @current ||=
        begin
          ids = @pod.seatings.map(&:event_participant_id)
          found = Result.current.where(round: @round, event_participant_id: ids).index_by(&:event_participant_id)
          ids.index_with { |id| found[id] }
        end
      return @current[participant.id] if @current.key?(participant.id)

      Result.current.find_by(round: @round, event_participant: participant)
    end

    def update(participant, type)
      result = current_for(participant) || Result.new(round: @round, event_participant: participant)
      result.update!(type: type, recorded_by_user_id: @by&.id, **games_for(participant))
      result.becomes(type.constantize)
    end

    # The superseded_by foreign key is deferred, so the old row can point at the new id first and
    # free the partial unique index before the new row is inserted.
    def supersede(participant, type)
      id = SecureRandom.uuid
      current_for(participant)&.update_columns(superseded_by_id: id, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      Result.create!(id: id, type: type, round: @round, event_participant: participant, recorded_by_user_id: @by&.id,
                     **games_for(participant))
    end

    # The game columns for one seat: the score as given for the winner and a draw, mirrored for the loser.
    # An unscored 1v1 rewrite (Penalty, time called) resets them so stale games never feed the tiebreakers.
    def games_for(participant)
      return {} if @score.nil? && !@round.event.one_v_one?
      return { games_won: 0, games_lost: 0, games_drawn: 0 } if @score.nil?

      won, lost, drawn = @type == "Draw" || participant == @winner ? @score : @score.values_at(1, 0, 2)
      { games_won: won, games_lost: lost, games_drawn: drawn }
    end
  end
end
