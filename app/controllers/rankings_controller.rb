# frozen_string_literal: true

# /rankings (spec M13): ranking points, Elo leaderboard and teams, narrowed by the URL filters. While a module is
# paused (config/features.yml) what belongs to it is left out: the Teams tab and filter without teams, the format
# filter without 1v1 (everything is Commander / cEDH).
class RankingsController < ApplicationController
  allow_unauthenticated_access

  BOARDS = { "points" => :points, "elo" => :elo, "teams" => :teams_board }.freeze
  TABS = BOARDS.keys.freeze
  LIMIT = 20

  helper_method :ranking_tabs

  def show
    @tab = ranking_tabs.include?(params[:tab]) ? params[:tab] : "points"
    @board = Rankings::Board.new(board_params, tab: @tab)
    @rows = @board.public_send(BOARDS.fetch(@tab))
    @all = params[:all] == "1"
    @summary = @board.summary
  end

  private

  def ranking_tabs = Features.on?(:teams) ? TABS : TABS - ["teams"]

  def board_params
    filters = params.permit(:season, :country, :organizer, :play, :team, :q, :sort)
    filters = filters.except(:team) unless Features.on?(:teams)
    Features.on?(:one_v_one) ? filters : filters.except(:play)
  end
end
