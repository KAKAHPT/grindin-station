# frozen_string_literal: true

# The public event lists (/events, /tournaments, /leagues, /circuits/:id) render shared/_event_ticket: covers and
# organizers preloaded, enrolled counts and latest published round numbers in one query each.
module EventTickets
  extend ActiveSupport::Concern

  FILTER_KEYS = %i[q season country organizer play].freeze
  SEASON_SQL = "EXTRACT(YEAR FROM events.start_time)::integer"

  private

  # Visible (not draft or canceled) events of a type, upcoming soonest first or past latest first, one page;
  # except: events already shown elsewhere on the page (the viewer's running now); filters: from ticket_filters.
  def ticket_scope(klass, past:, except: [], filters: {})
    scope = filter_tickets(klass.visible.where.not(id: except.map(&:id)), filters)
    ticket_preload(past ? scope.past.order(start_time: :desc) : scope.upcoming.order(:start_time))
      .page(params[:page]).load
  end

  # The /events filters from the URL (spec M13 D13), unknown values dropped: q, season (Integer), country,
  # organizer ([id, name, handle] of a listed organizer) and play (the format; `format` is Rails' request format).
  def ticket_filters # rubocop:disable Metrics/AbcSize,Metrics/MethodLength -- one entry per filter
    @ticket_filters ||=
      begin
        given = params.permit(*FILTER_KEYS)
        options = ticket_filter_options
        {
          q: given[:q].to_s.strip.presence,
          season: given[:season].to_i.presence_in(options[:seasons]),
          country: given[:country].to_s.upcase.presence_in(options[:countries]),
          organizer: options[:organizers].find { |_, _, handle| handle == given[:organizer] },
          play: given[:play].presence_in(Event::FORMATS)
        }.compact
      end
  end

  # The filter bar's choices over the visible tournaments and leagues, one query each: start years newest first,
  # countries and [id, name, handle] of the organizers by name.
  def ticket_filter_options
    @ticket_filter_options ||=
      begin
        visible = visible_events
        {
          seasons: visible.distinct.pluck(Arel.sql(SEASON_SQL)).sort.reverse,
          countries: visible.where.not(country: nil).distinct.order(:country).pluck(:country),
          organizers: ticket_filter_organizers(visible)
        }
      end
  end

  # Tournaments and leagues in one query: the state enum lives on the subclasses, and both map the hidden states
  # (draft, canceled) to the same integers, so the base class can filter them by value.
  def visible_events = Event.where.not(state: Tournament.states.values_at(*Event::HIDDEN_STATES))

  def ticket_filter_organizers(events)
    EventOrganizer.joins(:user).where(id: events.select(:event_organizer_id))
      .where(users: { anonymized_at: nil }).where.not(users: { handle: nil })
      .order("users.name").pluck(:id, "users.name", "users.handle")
  end

  def filter_tickets(scope, filters)
    scope = scope.where({ country: filters[:country], format: filters[:play] }.compact)
    scope = scope.where(event_organizer_id: filters[:organizer].first) if filters[:organizer]
    scope = scope.where("#{SEASON_SQL} = ?", filters[:season]) if filters[:season]
    filters[:q] ? search_tickets(scope, filters[:q]) : scope
  end

  # The event name or address (spec M13 ruling R2: not the organizer, which has its own filter).
  def search_tickets(scope, text)
    scope.where("events.name ILIKE :q OR events.address ILIKE :q", q: "%#{Event.sanitize_sql_like(text)}%")
  end

  # The signed-in viewer's own events of a type running now (none for a visitor).
  def ongoing_tickets(klass) = ticket_preload(klass.for_player(current_user&.player).ongoing).to_a

  def ticket_preload(scope) = scope.preload(cover_attachment: :blob, event_organizer: :user)

  def enrolled_counts(events)
    Event.load_latest_published_round_numbers(events)
    EventParticipant.enrolled.where(event_id: events.map(&:id)).group(:event_id).count
  end
end
