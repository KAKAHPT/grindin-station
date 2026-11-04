# frozen_string_literal: true

# The landing (/): the fair-seats story, the organisers' waiting list and the next public tournaments.
class PagesController < ApplicationController
  allow_unauthenticated_access
  layout "public"

  UPCOMING_LIMIT = 6

  # Not started yet, or running now (a live swiss or cut); finished, draft and canceled ones are left out.
  def self.listed_tournaments
    Tournament.visible.where.not(state: :finished).merge(Tournament.upcoming.or(Tournament.ongoing))
  end

  def home
    listed = self.class.listed_tournaments
    @open_count = listed.registration_open.count
    @upcoming = listed.order(:start_time).limit(UPCOMING_LIMIT)
      .preload(cover_attachment: :blob, event_organizer: :user).to_a
    @enrolled = EventParticipant.enrolled.where(event_id: @upcoming.map(&:id)).group(:event_id).count
    @waitlist_signup = WaitlistSignup.new
  end
end
