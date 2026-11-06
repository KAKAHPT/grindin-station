# frozen_string_literal: true

module Posts
  # The social feed's filters, read from the request, and the posts they select (ordered, not yet paginated).
  # Filters: scope (everyone | following, signed-in only), circuit, play (a play pool), event, organizer (handle),
  # sort (new | top), mine (events the viewer played or organizes), mentions (posts naming the viewer).
  class Feed
    attr_reader :viewer, :circuit, :play, :event, :organizer, :sort, :scope

    def initialize(params, viewer)
      @params = params
      @viewer = viewer
      @sort = params[:sort] == "top" ? "top" : "new"
      @scope = read_scope
      read_targets
    end

    def mine? = viewer.present? && @params[:mine] == "1"
    def mentions? = viewer.present? && @params[:mentions] == "1"
    def top? = sort == "top"
    def following? = scope == "following"

    # Organizers whose events have posts, A–Z: the organizer filter's choices.
    def organizers
      @organizers ||= EventOrganizer.joins(:user).where(id: posted_events.select(:event_organizer_id)).includes(:user)
        .order(Arel.sql("LOWER(users.name)")).to_a
    end

    def posts
      relation = filtered(Post.visible)
      top? ? relation.top_this_week : relation.recent
    end

    # The filters as URL params (for links that change one of them).
    def url_params # rubocop:disable Metrics/CyclomaticComplexity -- one key per filter
      { scope: scope, circuit: circuit&.id, play: play, event: event&.id, organizer: organizer&.user&.handle,
        sort: (sort if top?), mine: ("1" if mine?), mentions: ("1" if mentions?) }.compact
    end

    private

    # The circuit, play pool, event and organizer named by the params, when they exist.
    def read_targets
      @circuit = Circuit.find_by(id: @params[:circuit]) if @params[:circuit].present?
      @play = @params[:play].presence if Event::PLAYS.include?(@params[:play].to_s)
      read_event_and_organizer
    end

    def read_event_and_organizer
      @event = posted_events.find_by(id: @params[:event]) if @params[:event].present?
      @organizer = organizers.find { |organizer| organizer.user&.handle == @params[:organizer] }
    end

    def read_scope
      return "everyone" unless viewer

      requested = @params[:scope].presence || viewer.feed_scope
      User::FEED_SCOPES.include?(requested) ? requested : "everyone"
    end

    def filtered(relation)
      relation = relation.in_circuit(circuit) if circuit
      relation = relation.about_play(play) if play
      relation = relation.where(event: event) if event
      relation = relation.about_organizer(organizer) if organizer
      viewer_filters(relation)
    end

    def viewer_filters(relation)
      relation = relation.about_events_of(viewer) if mine?
      relation = relation.mentioning(viewer) if mentions?
      following? ? relation.followed_by(viewer) : relation
    end

    def posted_events
      Event.where(id: Post.select(:event_id)).where.not(state: Tournament.states.values_at(*Event::HIDDEN_STATES))
    end
  end
end
