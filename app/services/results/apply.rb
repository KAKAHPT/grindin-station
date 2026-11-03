# frozen_string_literal: true

module Results
  # Records a pod's result. While the round is open the rows are updated in place; once it is
  # closed (finished_at) they are never overwritten: fresh rows are written and the old ones
  # point at them through superseded_by, so only Result.current feeds scoring.
  class Apply
    Outcome = Data.define(:results, :warning)

    def self.call(pod:, type:, winner: nil, by: nil)
      new(pod: pod, type: type, winner: winner, by: by).call
    end

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

    def initialize(pod:, type:, winner:, by:)
      @pod = pod
      @round = pod.round
      @type = self.class.type_for(@round, type)
      @winner = winner
      @by = by
    end

    def call
      results =
        Result.transaction do
          closed = Round.finished.exists?(@round.id) # fresh: the round may have closed since it was loaded
          assignments.map { |participant, type| closed ? supersede(participant, type) : update(participant, type) }
        end
      Outcome.new(results: results, warning: self.class.warning_for(@pod))
    end

    private

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

    def current_for(participant)
      Result.current.find_by(round: @round, event_participant: participant)
    end

    def update(participant, type)
      result = current_for(participant) || Result.new(round: @round, event_participant: participant)
      result.update!(type: type, recorded_by_user_id: @by&.id)
      result.becomes(type.constantize)
    end

    # The superseded_by foreign key is deferred, so the old row can point at the new id first and
    # free the partial unique index before the new row is inserted.
    def supersede(participant, type)
      id = SecureRandom.uuid
      current_for(participant)&.update_columns(superseded_by_id: id, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      Result.create!(id: id, type: type, round: @round, event_participant: participant, recorded_by_user_id: @by&.id)
    end
  end
end
