# frozen_string_literal: true

class TournamentsController < ApplicationController
  include PublicEvent

  skip_before_action :require_authentication
  def index
    scope = Tournament.with_attached_cover.where.not(state: %i[draft canceled]).preload(:rounds)

    case params[:filter]
    when "past"
      scope = scope.past
      @title = "Past tournaments"
    else
      scope = scope.upcoming
      @title = "Upcoming tournaments"
    end

    @tournaments = scope.page params[:page]

    @ongoing = Tournament.for_player(current_user&.player).ongoing
  end

  # The event page lives at /t/:slug (every event has one). A hidden event is not found, as there.
  def show
    tournament = ensure_public!(Tournament.find(params[:id]))
    flash.keep # notices from enrol/cancel, which still redirect here
    redirect_to play_event_path(tournament.slug, locale: params[:locale])
  end
end
