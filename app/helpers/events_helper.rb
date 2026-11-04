# frozen_string_literal: true

# The public event page (/t/:slug).
module EventsHelper
  EVENT_STATE_TONES = {
    draft: :warn, registration_open: :ok, registration_closed: :warn, swiss: :info,
    single_elimination: :info, finished: :info, canceled: :bad
  }.with_indifferent_access.freeze

  # "Registration open", "Swiss round 3", "Top 16", ...; round_number is the latest published round.
  def event_state_chip(event, round_number)
    label =
      case event.state
      when "swiss" then t("play.events.state.swiss", number: round_number || 1)
      when "single_elimination" then t("play.events.state.single_elimination", size: event.top_cut_size)
      else t("play.events.state.#{event.state}")
      end
    desk_chip(EVENT_STATE_TONES.fetch(event.state)) { label }
  end
end
