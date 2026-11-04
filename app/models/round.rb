# frozen_string_literal: true

# Model representing a round in the tournament
class Round < ApplicationRecord
  belongs_to :event, counter_cache: true
  has_many :event_participants, -> { enrolled.not_eliminated }, through: :event
  has_many :pods, dependent: :destroy
  has_many :seatings, through: :pods
  has_many :results, -> { current }, dependent: nil, inverse_of: :round
  has_many :all_results, class_name: "Result", dependent: :destroy, inverse_of: :round

  scope :published, -> { where(published: true) }
  scope :finished, -> { where.not(finished_at: nil) }
  scope :swiss_rounds, -> { where(type: "SwissRound") }
  scope :play_rounds, -> { where(is_play_round: true) }
  scope :finals_rounds, -> { where(is_finals_round: true) }

  after_create :create_pods
  after_update :round_finished
  after_update_commit :broadcast_live, if: -> { saved_changes.keys.intersect?(%w[published started_at finished_at]) }

  def finished?
    pods.all?(&:finished?)
  end

  def started?
    started_at.present?
  end

  def past?
    finished_at.present?
  end

  # Pods holding the round open: no result yet, a disputed result, or a judge call still open.
  def blocking_pods
    pods.preload(:judge_calls, :seatings, round: :results).sort_by(&:number)
      .reject { |pod| pod.report_status == :completed && !pod.open_judge_call? }
  end

  def closable?
    blocking_pods.empty?
  end

  def advance_tournament!
    # No-op default. Override in subclasses (SwissRound, SingleEliminationRound).
  end

  def publish!
    update!(published: true)
  end
  alias published! publish!

  def byes
    results
      .where(type: "Advance")
      .where.not(event_participant_id: seatings.select(:event_participant_id))
  end

  # Byes, best ranked first; their participants come from one standings load.
  def ranked_byes
    byes = self.byes.to_a
    return byes if byes.empty?

    ranked = EventParticipant.standings_for(event).index_by(&:id)
    byes.each { |result| result.association(:event_participant).target = ranked.fetch(result.event_participant_id) }
    byes.sort_by { |result| -result.event_participant.rank_score }
  end

  private

  # Publishing, starting or closing reloads the staff round pages. Publishing, or reopening after the
  # next round was undone, also pushes every table.
  def broadcast_live
    tables = saved_change_to_published?(to: true) || saved_change_to_finished_at?(to: nil)
    Live::BroadcastRoundJob.perform_later(self, tables: tables, request_id: Turbo.current_request_id)
  end

  def round_finished
    return unless finished_at.present? && finished_at_previously_changed?

    ::Standings::Snapshot.call(event, self) if is_a?(SwissRound) && event.is_a?(Tournament)
    advance_tournament!
  end
end
