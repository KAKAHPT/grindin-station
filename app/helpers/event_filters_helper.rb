# frozen_string_literal: true

# The /events filter bar and chips (spec M13 D13) over EventTickets#ticket_filters.
module EventFiltersHelper
  EVENT_FILTER_LABELS = { q: :search_chip, play: :format }.freeze

  # The active filters as URL params (the organizer by handle).
  def event_filter_query(filters)
    filters.merge(organizer: filters[:organizer]&.last).compact
  end

  # Fields for shared/_filter_bar.
  def event_filter_fields(filters, options) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength -- one entry per filter
    [
      [:q, :search, t("events.filters.search"), filters[:q]],
      [:season, :segment, options[:seasons].map { |year| [year.to_s, year.to_s] } + all_option(:all_seasons),
       filters[:season].to_s, t("events.filters.season")],
      [:country, :select, all_option(:all_countries) + options[:countries].map { |code| [country_name(code), code] },
       filters[:country], t("events.filters.country")],
      [:organizer, :select, all_option(:all_organizers) + options[:organizers].map { |_, name, handle| [name, handle] },
       filters[:organizer]&.last, t("events.filters.organizer")],
      [:play, :select, all_option(:all_formats) + Event::PLAYS.map { |play| [play_label(play), play] },
       filters[:play], t("events.filters.format")],
      [:sort, :select, sort_options(EventTickets::SORTS, "events"), params[:sort].presence_in(EventTickets::SORTS),
       t("events.sort.label")]
    ]
  end

  # [[label, value]] of a list's sort select, each option read as "Sort by: …" so it is not taken for a filter.
  def sort_options(sorts, scope)
    sorts.map { |sort| ["#{t("#{scope}.sort.label")}: #{t("#{scope}.sort.#{sort}")}", sort] }
  end

  # [[label, value, url without it]] for shared/_filter_chips; base: the params every link keeps (filter, locale).
  def event_filter_chips(filters, base)
    query = event_filter_query(filters)
    values = event_filter_values(filters)
    %i[season country organizer play q].select { |key| query.key?(key) }.map do |key|
      label = t("events.filters.#{EVENT_FILTER_LABELS.fetch(key, key)}")
      [label, values[key], events_path(**base, **query.except(key))]
    end
  end

  private

  def all_option(key) = [[t("events.filters.#{key}"), ""]]

  # The chip texts of the active filters.
  def event_filter_values(filters)
    {
      season: filters[:season].to_s, country: (country_name(filters[:country]) if filters[:country]),
      organizer: filters[:organizer]&.second, q: filters[:q],
      play: (play_label(filters[:play]) if filters[:play])
    }
  end
end
