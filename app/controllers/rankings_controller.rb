# frozen_string_literal: true

# /rankings (spec M13): ranking points, Elo leaderboard and teams, narrowed by the URL filters.
class RankingsController < ApplicationController
  allow_unauthenticated_access

  BOARDS = { "points" => :points, "elo" => :elo, "teams" => :teams_board }.freeze
  TABS = BOARDS.keys.freeze
  LIMIT = 20

  def show
    @board = Rankings::Board.new(params.permit(:season, :country, :organizer, :format, :team, :q, :sort))
    @tab = TABS.include?(params[:tab]) ? params[:tab] : "points"
    @rows = @board.public_send(BOARDS.fetch(@tab))
    @all = params[:all] == "1"
    @summary = @board.summary
  end
end
