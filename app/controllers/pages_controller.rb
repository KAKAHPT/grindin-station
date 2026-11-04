# frozen_string_literal: true

# The landing (/): the fair-seats story, the organisers' waiting list and the next public tournaments.
class PagesController < ApplicationController
  allow_unauthenticated_access
  layout "public"

  UPCOMING_LIMIT = 6

  def home
    scope = Tournament.visible.upcoming.order(:start_time).limit(UPCOMING_LIMIT)
    @upcoming = scope.preload(cover_attachment: :blob, event_organizer: :user).to_a
    @enrolled = EventParticipant.enrolled.where(event_id: @upcoming.map(&:id)).group(:event_id).count
    @waitlist_signup = WaitlistSignup.new
  end
end
