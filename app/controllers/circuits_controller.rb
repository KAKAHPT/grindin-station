# frozen_string_literal: true

class CircuitsController < ApplicationController
  include EventTickets

  skip_before_action :require_authentication

  # Draft and canceled events are left out of the lists and the counts.
  def index
    @circuits = Circuit.preload(event_organizer: :user).with_attached_banner.order(featured: :desc, created_at: :desc)
      .page(params[:page])
    ids = @circuits.map(&:id)
    @tournament_counts = Tournament.visible.where(circuit_id: ids).group(:circuit_id).count
    @league_counts = League.visible.where(circuit_id: ids).group(:circuit_id).count
  end

  STANDINGS_SHOWN = 16

  # Standings show the top 16 unless ?all=1; events show the upcoming ones (end_time from now) unless ?filter=past.
  def show
    @circuit = Circuit.preload(event_organizer: :user).find(params[:id])
    @standings = @circuit.standings.preload(player: :user).to_a
    @show_all = params[:all].present?
    @past = params[:filter] == "past"
    load_events
    load_posts
  end

  private

  # The circuit's feed: the latest posts about its events.
  def load_posts
    @posts = Post.in_circuit(@circuit).visible.recent.preload(:event, user: { avatar_attachment: :blob }).limit(3).to_a
    @posts_count = Post.in_circuit(@circuit).visible.count
    @liked_ids =
      if current_user
        PostLike.where(user: current_user,
                       post_id: @posts.map(&:id)).pluck(:post_id).to_set
      else
        Set.new
      end
  end

  def load_events
    @tournaments = circuit_events(@circuit.tournaments)
    @leagues = circuit_events(@circuit.leagues)
    @enrolled = enrolled_counts(@tournaments + @leagues)
  end

  def circuit_events(scope) = ticket_preload(scope.visible.order(start_time: :desc)).to_a
end
