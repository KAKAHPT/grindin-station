# frozen_string_literal: true

# What a player does at a league's tables (the Tables tab of the league page): open one, join, leave, close,
# and at a full table report, confirm or contest the result, ask to cancel it and start its clock.
class LeagueTablesController < ApplicationController
  include PublicEvent

  before_action :load_league
  before_action :load_table, except: :create

  rescue_from Leagues::Tables::NotAllowed do |error|
    redirect_to tables_tab, alert: t("leagues.tables.not_allowed.#{error.message}")
  end
  rescue_from Results::NotAllowed do |error|
    redirect_to tables_tab, alert: t("results.not_allowed.#{error.message}")
  end

  def create
    Leagues::Tables::Open.call(league: @league, participant: participant)
    done("opened")
  end

  def join
    Leagues::Tables::Join.call(table: @table, participant: participant)
    done(@table.reload.filled? ? "filled" : "joined")
  end

  def leave
    Leagues::Tables::Leave.call(table: @table, participant: participant!)
    done("left")
  end

  def close
    Leagues::Tables::Close.call(table: @table, participant: participant!)
    done("closed")
  end

  # A player reports their own win ("win") or a draw ("draw"); nobody reports a win for someone else.
  def report
    type = { "win" => "Win", "draw" => "Draw" }.fetch(params[:result].to_s) { raise Results::NotAllowed, "invalid_type" }
    Results::Report.call(pod: pod!, participant: participant!, type: type, winner: (participant! if type == "Win"))
    done("reported")
  end

  def confirm
    Results::Confirm.call(pod: pod!, participant: participant!)
    done("confirmed")
  end

  def contest
    Results::Contest.call(pod: pod!, participant: participant!, reason: params[:reason])
    done("contested")
  end

  def cancel
    Leagues::Tables::RequestCancel.call(table: @table, participant: participant!, reason: params[:reason])
    done("cancel_requested")
  end

  def clock
    raise Leagues::Tables::NotAllowed, "not_member" unless pod!.seated?(participant!)

    pod!.update!(clock_started_at: Time.current) if pod!.clock_started_at.nil?
    done("clock_started")
  end

  private

  def load_league
    @league = ensure_public!(League.find(params.expect(:league_id)))
  end

  def load_table
    @table = @league.league_tables.find(params.expect(:id))
  end

  # The signed-in player's registration in the league, or nil.
  def participant
    @participant ||= current_user.player && @league.event_participants.find_by(player: current_user.player)
  end

  def participant! = participant || raise(Leagues::Tables::NotAllowed, "not_enrolled")

  def pod! = @table.pod || raise(Leagues::Tables::NotAllowed, "not_in_play")

  # "My round" while the player sits at a table, the list of tables otherwise.
  def tables_tab
    seated = participant && LeagueTableSeat.active.exists?(event_participant_id: participant.id)
    league_path(@league, tab: seated ? "mine" : "tables", locale: params[:locale])
  end

  # Everyone looking at the league's tables sees the change.
  def done(key)
    Turbo::StreamsChannel.broadcast_refresh_later_to(@league, :tables)
    redirect_to tables_tab, notice: t("leagues.tables.notices.#{key}")
  end
end
