# frozen_string_literal: true

# A player's own result at a table of a league's top cut: the winner says "I won" and the table closes at once.
# The organizer still closes the round, and can correct a table until then (Organizer::LeaguesController#enter_result).
class LeagueCutPodsController < ApplicationController
  include PublicEvent

  rescue_from Results::NotAllowed do |error|
    redirect_to mine_tab, alert: t("results.not_allowed.#{error.message}")
  end

  def report
    league = ensure_public!(League.find(params.expect(:league_id)))
    pod = Pod.joins(:round).where(rounds: { event_id: league.id, type: "LeagueCutRound", finished_at: nil })
      .find(params.expect(:id))
    win!(pod, current_user.player && league.event_participants.find_by(player: current_user.player))
    Turbo::StreamsChannel.broadcast_refresh_later_to(league, :tables)
    redirect_to mine_tab, notice: t("leagues.tables.notices.cut_reported")
  end

  private

  def win!(pod, participant)
    Pod.transaction do
      pod.lock!
      raise Results::NotAllowed, "not_seated" unless pod.seated?(participant)
      raise Results::NotAllowed, "already_finished" if pod.finished?

      Results::Apply.call(pod: pod, type: "Win", winner: participant, by: nil)
      pod.update!(reported_by_participant_id: participant.id, reported_at: Time.current)
    end
  end

  def mine_tab = league_path(params.expect(:league_id), tab: "mine", locale: params[:locale])
end
