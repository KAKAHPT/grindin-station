# frozen_string_literal: true

class Pod < ApplicationRecord
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

  def open_judge_call?
    judge_calls.open_or_acknowledged.exists?
  end

  def finished?
    results.size == event_participants.size
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

  def seating_rng
    Random.new(Digest::SHA256.hexdigest([event.seed.to_i, round.number, number].join("-")).to_i(16))
  end
end
