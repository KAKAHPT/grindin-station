# frozen_string_literal: true

# Finds the event of a public /t/:slug page. A draft or canceled event exists only for its staff.
module PublicEvent
  extend ActiveSupport::Concern

  HIDDEN_STATES = Event::HIDDEN_STATES

  private

  # The cover is preloaded for the event header card (attachment + blob only, no variant/preview lookups).
  def find_public_event!
    ensure_public!(Tournament.preload(cover_attachment: :blob).find_by!(slug: params.expect(:slug)))
  end

  # Works for any Event (tournament or league); returns the event.
  def ensure_public!(event)
    hidden = event.state.in?(HIDDEN_STATES) && !current_user&.staff_role_for(event)
    raise ActiveRecord::RecordNotFound if hidden

    event
  end
end
