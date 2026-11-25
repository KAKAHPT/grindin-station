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

  # params[:result]: a seated player's participant id (the winner) or "draw".
  def report
    winner = pod!.event_participants.find_by(id: params[:result]) unless params[:result] == "draw"
    Results::Report.call(pod: pod!, participant: participant!, type: winner ? "Win" : "Draw", winner: winner)
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

  def tables_tab = league_path(@league, tab: "tables", locale: params[:locale])

  # Everyone looking at the league's tables sees the change.
  def done(key)
    Turbo::StreamsChannel.broadcast_refresh_later_to(@league, :tables)
    redirect_to tables_tab, notice: t("leagues.tables.notices.#{key}")
  end
end
