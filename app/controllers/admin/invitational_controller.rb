# frozen_string_literal: true

module Admin
  # /admin/invitational: the invitational leaderboard of a season (spec M13 D16) and its CSV export (audited
  # data_exported). Tiers are admin-only: nothing here is public.
  class InvitationalController < BaseController
    before_action :load_season

    def show
      @rows = Invitational.rows(season: @season)
    end

    def export
      Audit.record("data_exported", kind: "invitational", season: season_param)
      send_data Exports::Invitational.call(season: @season), type: "text/csv; charset=utf-8",
                                                             filename: "invitational-#{season_param}.csv"
    end

    private

    # ?season=all → every season (nil); a year with contributions (or the current one), else the current year.
    def load_season
      current = Date.current.year
      @seasons = ([current] + Invitational.seasons).uniq.sort.reverse
      @season = params[:season] == "all" ? nil : (@seasons.find { |year| year.to_s == params[:season] } || current)
    end

    def season_param = (@season || "all").to_s
  end
end
