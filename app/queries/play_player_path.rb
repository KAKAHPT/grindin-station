# frozen_string_literal: true

# One participant's path through an event: a step per closed round they were in, with the table, the seat,
# their result and who sat with them. Read by the final standings' player dialog (Play::StandingsController#player).
class PlayPlayerPath
  Step = Data.define(:round, :pod, :seat, :result, :others, :winner)
  # Chip tone of each outcome (status_chip).
  TONES = { "win" => :accent, "advance" => :accent, "draw" => :ink, "bye" => :ink, "loss" => :muted,
            "eliminated" => :muted, "penalty" => :danger, "none" => :muted }.freeze

  def self.call(event, participant) = new(event, participant).steps

  def initialize(event, participant)
    @event = event
    @participant = participant
  end

  def steps
    rounds.filter_map do |round|
      pod = round.pods.find { |p| p.seatings.any? { |s| s.event_participant_id == @participant.id } }
      result = round.results.find { |r| r.event_participant_id == @participant.id }
      step(round, pod, result) if pod || result
    end
  end

  private

  def rounds
    @event.rounds.finished.order(:number)
      .preload(:results, pods: { seatings: { event_participant: { player: :user } } }).to_a
  end

  def step(round, pod, result)
    seatings = pod ? pod.seatings.sort_by(&:order) : []
    mine = seatings.find { |s| s.event_participant_id == @participant.id }
    Step.new(round: round, pod: pod, seat: mine&.order, result: outcome(result, pod),
             others: seatings - [mine], winner: winner_id(round, seatings))
  end

  # The participant who won (or advanced from) the table, if any.
  def winner_id(round, seatings)
    seated = seatings.map(&:event_participant_id)
    won = round.results.find { |r| r.class.in?([Win, Advance]) && seated.include?(r.event_participant_id) }
    won&.event_participant_id
  end

  # win, loss, draw, penalty, advance, eliminated, bye (a result with no table) or none (no result recorded).
  def outcome(result, pod)
    return "none" unless result
    return "bye" if pod.nil?

    result.type.downcase
  end
end
