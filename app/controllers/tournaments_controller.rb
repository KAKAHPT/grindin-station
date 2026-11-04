# frozen_string_literal: true

class TournamentsController < ApplicationController
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

  # The event page lives at /t/:slug; the old page stays only for a tournament without a slug.
  def show
    slug = Tournament.where(id: params[:id]).pick(:slug)
    if slug.present?
      flash.keep # notices from enrol/cancel, which still redirect here
      return redirect_to(play_event_path(slug, locale: params[:locale]))
    end

    @tournament = Tournament.preload(rounds: :pods, event_participants: { player: :user }).find(params[:id])
  end
end
