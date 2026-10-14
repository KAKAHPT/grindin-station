# frozen_string_literal: true

class Pod < ApplicationRecord
  belongs_to :round
  has_one :event, through: :round

  has_many :seatings, -> { order(order: :asc) }, dependent: :destroy, inverse_of: :pod
  has_many :event_participants, through: :seatings
  has_many :results, lambda { |pod|
    unscope(where: { rounds: :finished_at }).where(results: { round_id: pod.round_id })
  }, through: :event_participants

  has_many :players, through: :event_participants
  has_many :users, through: :players

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
      weighted_seatings
    end

    self.candidates = []

    save!
  end

  def ranked_seatings
    candidates.sort_by.with_index { |p, i| [-p.rank_score, i] }.each.with_index do |participant, i|
      seatings.build(event_participant: participant, order: i + 1)
    end
  end

  def weighted_seatings
    ordered_candidates =
      candidates.shuffle.sort_by.with_index do |participant, i|
        (1..size).to_a.map do |position|
          participant.times_going_at(position)
        end + [-participant.rank_score, i]
      end

    build_seatings(ordered_candidates)
  end

  def build_seatings(ordered_candidates)
    ordered_candidates.each.with_index do |participant, i|
      seatings.build(event_participant: participant, order: i + 1)
    end
  end
end
