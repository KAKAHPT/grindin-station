# frozen_string_literal: true

class CircuitsController < ApplicationController
  include EventTickets

  skip_before_action :require_authentication

  # ?sort=: featured (featured first, then newest), name or organizer (by name, then circuit name).
  SORTS = %w[featured name organizer].freeze

  # The circuits, narrowed by the events' filter bar (search on the circuit name, organizer; season, country and
  # format through the circuit's visible events) and sorted. Draft and canceled events are left out of the lists
  # and the counts.
  def index
    @sort = params[:sort].to_s.presence_in(SORTS) || "featured"
    @filters = ticket_filters
    @filter_options = ticket_filter_options
    @circuits = filter_circuits(sorted_circuits, @filters).preload(event_organizer: :user).with_attached_banner
      .page(params[:page])
    @tournament_counts, @league_counts = event_counts(@circuits.map(&:id))
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

  # The filter bar's choices come from the events of circuits only.
  def visible_events = super.where.not(circuit_id: nil)

  def filter_circuits(scope, filters)
    scope = scope.where("circuits.name ILIKE ?", "%#{Circuit.sanitize_sql_like(filters[:q])}%") if filters[:q]
    scope = scope.where(event_organizer_id: filters[:organizer].first) if filters[:organizer]
    through_events = filters.slice(:season, :country, :play)
    return scope if through_events.empty?

    scope.where(id: filter_tickets(visible_events, through_events).select(:circuit_id))
  end

  def event_counts(ids)
    [Tournament.visible.where(circuit_id: ids).group(:circuit_id).count,
     League.visible.where(circuit_id: ids).group(:circuit_id).count]
  end

  def sorted_circuits
    case @sort
    when "name" then Circuit.order(name: :asc)
    when "organizer" then Circuit.joins(event_organizer: :user).order("users.name ASC", name: :asc)
    else Circuit.order(featured: :desc, created_at: :desc)
    end
  end

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
