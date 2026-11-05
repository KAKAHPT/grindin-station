# frozen_string_literal: true

module Admin
  # /admin/events: every tournament and league, newest first, filtered by GET params (search, state, play = one of
  # Event::PLAYS, tier, organizer handle); Featured and the tier (M13 D16) are editable here.
  class EventsController < BaseController
    PER_PAGE = 50

    FILTERS = %i[q state play tier organizer].freeze
    # Tournament and league states; the shared ones have the same integer in both.
    STATES = (Tournament.states.keys | League.states.keys).freeze

    def index
      # permit keeps only plain strings: ?q[]=x is dropped, not a 500.
      @filters = params.slice(*FILTERS).permit(*FILTERS)
      @events =
        filtered(Event.includes(event_organizer: :user)).order(created_at: :desc).page(params[:page]).per(PER_PAGE)
    end

    def featured
      event = Event.find(params.expect(:id))
      # Skips validations on purpose: an event that is otherwise invalid can still be featured.
      event.update_columns(featured: !event.featured, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      Audit.record("featured_changed", subject: event, event: event, featured: event.featured)
      redirect_to back_to_index, notice: t("admin.events.featured_saved")
    end

    # The rankings rebuild (debounced) writes the invitational points from the new tier.
    def tier
      event = Event.find(params.expect(:id))
      tier = params.expect(:tier).presence_in(Event::TIERS)
      return redirect_to back_to_index, alert: t("admin.events.tier_invalid") unless tier

      change_tier(event, tier) if tier != event.tier
      redirect_to back_to_index, notice: t("admin.events.tier_saved")
    end

    private

    def change_tier(event, tier)
      from = event.tier
      event.update_columns(tier: tier, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      Audit.record("tier_changed", subject: event, event: event, from: from, to: tier)
      Rankings::RebuildJob.schedule!
    end

    # The list with the filters and page the row was on (the forms send them as filters[...] and page, since the
    # tier filter and the new tier share a name).
    def back_to_index
      filters = params.fetch(:filters, {})
      filters = filters.respond_to?(:permit) ? filters.permit(*FILTERS) : {}
      admin_events_path(**filters.to_h.symbolize_keys.compact_blank, page: params[:page].presence)
    end

    def filtered(scope) # rubocop:disable Metrics/AbcSize -- one line per filter
      filters = @filters.to_h.symbolize_keys.compact_blank
      scope = play_scope(scope.where(filters.slice(:tier)), filters[:play])
      scope = state_scope(scope, filters[:state]) if filters[:state]
      scope = organizer_scope(scope, filters[:organizer]) if filters[:organizer]
      filters[:q] ? search(scope, filters[:q].strip) : scope
    end

    # An unknown play is ignored.
    def play_scope(scope, play) = play.in?(Event::PLAYS) ? scope.with_play(play) : scope

    def organizer_scope(scope, handle) = scope.where(event_organizer: organizers.where(users: { handle: handle }))

    # swiss/single_elimination are tournaments only, play/finals leagues only; an unknown state matches nothing.
    def state_scope(scope, state)
      klasses = [Tournament, League].select { |klass| klass.states.key?(state) }
      return scope.none if klasses.empty?

      scope.where(type: klasses.map(&:name), state: klasses.first.states.fetch(state))
    end

    # The event name or slug, or the organizer's name or e-mail.
    def search(scope, text)
      q = "%#{Event.sanitize_sql_like(text)}%"
      named = organizers.where("users.name ILIKE :q OR users.email_address ILIKE :q", q: q)
      by_organizer = scope.where(event_organizer: named)
      scope.where("events.name ILIKE :q OR events.slug ILIKE :q", q: q).or(by_organizer)
    end

    def organizers = EventOrganizer.joins(:user)
  end
end
