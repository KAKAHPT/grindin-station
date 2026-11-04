# frozen_string_literal: true

class Pod < ApplicationRecord # rubocop:disable Metrics/ClassLength
  belongs_to :round
  has_one :event, through: :round

  has_many :seatings, -> { order(order: :asc) }, dependent: :destroy, inverse_of: :pod
  has_many :event_participants, through: :seatings
  has_many :results, lambda { |pod|
    unscope(where: { rounds: :finished_at }).where(results: { round_id: pod.round_id, superseded_by_id: nil })
  }, through: :event_participants

  has_many :players, through: :event_participants
  has_many :users, through: :players
  has_many :judge_calls, dependent: :nullify
  belongs_to :reported_by, class_name: "EventParticipant", foreign_key: :reported_by_participant_id,
                           optional: true, inverse_of: false

  scope :publishable, -> { joins(:round).where.not(rounds: { finished_at: nil }) }

  attr_accessor :candidates

  validates(
    :number,
    {
      presence: true,
      uniqueness: { scope: :round_id },
      numericality: true,
      inclusion: { in: 1.. }
    }
  )

  after_initialize -> { @candidates = [] }

  # Report state shown on "my table" and on the pod card; a change is broadcast live.
  LIVE_ATTRIBUTES = %w[pending_result confirmations disputed review_requested_at extra_time
                       reported_by_participant_id reported_at].freeze
  after_update_commit :broadcast_live, if: -> { saved_changes.keys.intersect?(LIVE_ATTRIBUTES) }

  def open_judge_call?
    return judge_calls.any? { |call| call.status.in?(%w[open acknowledged]) } if judge_calls.loaded?

    judge_calls.open_or_acknowledged.exists?
  end

  # Current results of the seated players. #results depends on the pod and cannot be preloaded, so a
  # page with many pods preloads round: :results and seatings, and they are read from there.
  def current_results
    return results unless association(:seatings).loaded? && round.association(:results).loaded?

    seated = seatings.map(&:event_participant_id)
    round.results.select { |result| seated.include?(result.event_participant_id) }
  end

  def finished?
    current_results.size == seatings.size
  end

  # The event's result_confirmation, except that a cut table never closes on one player's word:
  # "none" needs the opponent's confirmation there, like "one".
  def result_confirmation
    mode = round.event.result_confirmation
    mode == "none" && round.is_a?(SingleEliminationRound) ? "one" : mode
  end

  def seated?(participant)
    participant.present? && seatings.exists?(event_participant_id: participant.id)
  end

  # :disputed, :completed (current results for every seat), :review (confirmation timed out),
  # :pending (a reported result awaiting confirmations) or :playing.
  def report_status
    if disputed? then :disputed
    elsif finished? then :completed
    elsif review_requested_at then :review
    elsif pending_result then :pending
    else :playing
    end
  end

  # Used when staff reports the pod: drops any player report, its confirmations and dispute.
  def clear_report_state!
    update!(pending_result: nil, confirmations: {}, disputed: false, review_requested_at: nil)
  end

  def force_candidate(candidate)
    candidates.push(candidate) unless full?
  end

  def full?
    candidates.size == size
  end

  def sit_participants!
    if round.is_a? SingleEliminationRound
      ranked_seatings
    elsif round.event.one_v_one?
      random_seatings
    else
      fair_seatings
    end

    self.candidates = []

    save!
  end

  def ranked_seatings
    candidates.sort_by.with_index { |p, i| [-p.rank_score, i] }.each.with_index do |participant, i|
      seatings.build(event_participant: participant, order: i + 1, assigned_by: "ranked")
    end
  end

  # 1v1 swiss: who sits first is a coin flip seeded like fair_seatings; no seat history.
  def random_seatings
    participants = candidates.sort_by(&:id)
    participants.reverse! if seating_rng.rand(2).zero?
    participants.each.with_index(1) do |participant, position|
      seatings.build(event_participant: participant, order: position, assigned_by: "random")
    end
  end

  # Swiss: Tournaments::SeatAssigner over the candidates' seat history, its tie-break seeded by
  # (event seed, round number, pod number). Digest, not Array#hash, which changes between processes.
  # Candidates are sorted by id first (they arrive shuffled), so the seed alone decides the tie-break.
  # No candidates (league pick-up pods build their seatings directly) leaves the seats as they are.
  def fair_seatings
    return if candidates.empty?

    participants = candidates.sort_by(&:id)
    seat_counts = participants.index_with(&:seat_counts)
    assigner = Tournaments::SeatAssigner.new(participants: participants, seat_counts: seat_counts, rng: seating_rng)
    assigner.order.each.with_index(1) do |participant, position|
      seatings.build(event_participant: participant, order: position, assigned_by: "fair", cost: assigner.cost)
    end
  end

  # A dispute moves the pod in or out of :completed, which changes the card's staff buttons: refresh the page too.
  def broadcast_live
    Live::BroadcastPodJob.perform_later(pod_id: id, refresh: saved_change_to_disputed?,
                                        request_id: Turbo.current_request_id)
  end

  def seating_rng
    Random.new(Digest::SHA256.hexdigest([round.event.seed.to_i, round.number, number].join("-")).to_i(16))
  end
end
