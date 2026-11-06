# frozen_string_literal: true

# The landing (/): the fair-seats story, the organisers' waiting list, the featured tournaments (up to three, left
# out of Upcoming) and the next public tournaments.
class PagesController < ApplicationController
  allow_unauthenticated_access
  layout "public"

  UPCOMING_LIMIT = 6
  FEATURED_LIMIT = 3

  # Not started yet, or running now (a live swiss or cut); finished, draft and canceled ones are left out.
  def self.listed_tournaments
    Tournament.visible.where.not(state: :finished).merge(Tournament.upcoming.or(Tournament.ongoing))
  end

  def home
    listed = self.class.listed_tournaments
    @open_count = listed.registration_open.count
    @featured = listed.where(featured: true).order(:start_time).limit(FEATURED_LIMIT).to_a
    @upcoming = listed.excluding(@featured).order(:start_time).limit(UPCOMING_LIMIT).to_a
    @enrolled = ticket_counts(@featured + @upcoming)
    load_extras
  end

  private

  # Up to three admin-featured circuits (an ECL season, a championship) under the featured tournaments, and the
  # waiting-list form.
  def load_extras
    @featured_circuits = Circuit.featured.with_attached_banner.preload(event_organizer: :user).order(:created_at)
      .limit(3).to_a
    @waitlist_signup = WaitlistSignup.new
  end

  # One preload, the latest published rounds and one count for the featured and the upcoming tickets together.
  def ticket_counts(events)
    associations = [{ cover_attachment: :blob }, { event_organizer: :user }]
    ActiveRecord::Associations::Preloader.new(records: events, associations: associations).call
    Event.load_latest_published_round_numbers(events)
    EventParticipant.enrolled.where(event_id: events.map(&:id)).group(:event_id).count
  end
end
