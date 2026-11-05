# frozen_string_literal: true

# The /events filter bar and chips (spec M13 D13) over EventTickets#ticket_filters.
module EventFiltersHelper
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
      [:format, :select, all_option(:all_formats) + Event::FORMATS.map { |f| [t("events.filters.formats.#{f}"), f] },
       filters[:format], t("events.filters.format")]
    ]
  end

  # [[label, value, url without it]] for shared/_filter_chips; base: the params every link keeps (filter, locale).
  def event_filter_chips(filters, base)
    query = event_filter_query(filters)
    values = event_filter_values(filters)
    %i[season country organizer format q].select { |key| query.key?(key) }.map do |key|
      [t("events.filters.#{key == :q ? :search_chip : key}"), values[key], events_path(**base, **query.except(key))]
    end
  end

  private

  def all_option(key) = [[t("events.filters.#{key}"), ""]]

  # The chip texts of the active filters.
  def event_filter_values(filters)
    {
      season: filters[:season].to_s, country: (country_name(filters[:country]) if filters[:country]),
      organizer: filters[:organizer]&.second, q: filters[:q],
      format: (t("events.filters.formats.#{filters[:format]}") if filters[:format])
    }
  end
end
