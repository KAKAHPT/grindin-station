# frozen_string_literal: true

# Finds the event of a public /t/:slug page. A draft or canceled event exists only for its staff.
module PublicEvent
  extend ActiveSupport::Concern

  HIDDEN_STATES = %w[draft canceled].freeze

  private

  def find_public_event!
    event = Tournament.find_by!(slug: params.expect(:slug))
    hidden = event.state.in?(HIDDEN_STATES) && !current_user&.staff_role_for(event)
    raise ActiveRecord::RecordNotFound if hidden

    event
  end
end
