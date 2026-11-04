# frozen_string_literal: true

# The 16-player tournament the feed tests read: round 1 closed (pod 1 seat 1 wins, pod 2 seat 2 wins,
# pod 3 draws, pod 4 seat 4 wins), round 2 published and started 10 minutes ago with pod 1 reported
# (seat 1 wins, round still open) and pod 2 awaiting confirmations.
module FeedTournament
  ROUND_TWO_STARTED_AT = Time.utc(2026, 11, 4, 15, 0, 0)

  def build_feed_tournament
    @t = TournamentBuilder.build(players: 16, organizer: event_organizers(:standard_organizer))
    @t.update_columns(swiss_rounds_count: 2, top_cut_size: 4, round_minutes: 80) # rubocop:disable Rails/SkipsModelValidations
    @round1 = @t.rounds.create!(type: SwissRound, number: 1)
    @round1.update_columns(started_at: ROUND_TWO_STARTED_AT - 2.hours) # rubocop:disable Rails/SkipsModelValidations
    TournamentBuilder.play_round!(@t, winners: { 1 => 0, 2 => 1, 3 => :draw, 4 => 3 })
    @round2 = @t.rounds.create!(type: SwissRound, number: 2)
    @round2.update_columns(published: true, started_at: ROUND_TWO_STARTED_AT) # rubocop:disable Rails/SkipsModelValidations
    report_round_two
    @t.reload
  end

  # Seated participants of the pod, seat 1 first.
  def seated(round, pod_number)
    round.pods.find_by!(number: pod_number).seatings.map(&:event_participant)
  end

  private

  def report_round_two
    seated(@round2, 1).each_with_index do |participant, i|
      (i.zero? ? Win : Loss).create!(round: @round2, event_participant: participant)
    end
    @round2.pods.find_by!(number: 2).update!(pending_result: { "winner" => seated(@round2, 2).first.id })
  end
end
