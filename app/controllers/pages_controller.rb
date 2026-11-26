# frozen_string_literal: true

# The landing (/): the fair-seats story, the organisers' waiting list, the featured tournaments (up to nine on a
# rail, left out of Upcoming) and the next public tournaments. Also /fairness, the public seat-fairness report, and
# /privacy, the privacy notice.
class PagesController < ApplicationController
  include EventTickets

  allow_unauthenticated_access
  layout "public"

  UPCOMING_LIMIT = 6
  FEATURED_LIMIT = 9
  FEATURED_CIRCUITS_LIMIT = 9

  # Not over yet by its dates, or running now (a live swiss or cut); finished, draft and canceled ones are left out.
  def self.listed_tournaments
    Tournament.visible.where.not(state: :finished).merge(Tournament.not_ended.or(Tournament.ongoing))
  end

  def home
    listed = self.class.listed_tournaments
    @open_count = listed.registration_open.count
    @featured = listed.where(featured: true).order(:start_time).limit(FEATURED_LIMIT).to_a
    @upcoming = upcoming_scope(listed).excluding(@featured).order(:start_time).limit(UPCOMING_LIMIT).to_a
    @enrolled = ticket_counts(@featured + @upcoming)
    load_extras
  end

  # /fairness: the seat report of real test tournaments (config/seat_fairness.json, regenerated with
  # RAILS_ENV=test bin/rails grindin:seat_report),
  # one block per round count, Grindin's weighted seats against seats drawn at random.
  def fairness
    @report = JSON.parse(Rails.root.join("config/seat_fairness.json").read)
    @rounds = @report["rounds"]
    @averages = %w[fair random].index_with { |seating| average_fair_rate(seating) }
  end

  # /privacy: what personal data the site keeps, why, for how long and the visitor's rights (texts in privacy.*).
  def privacy; end

  private

  # The Upcoming list narrowed to the chosen format (?play=) when it is one of the listed ones.
  def upcoming_scope(listed)
    @plays = Features.on?(:one_v_one) ? plays_present(listed) : []
    @play = params.permit(:play)[:play].presence_in(@plays)
    @play ? listed.with_play(@play) : listed
  end

  # The formats (Event::PLAYS) among the listed tournaments, in PLAYS order: the Upcoming filter shows these only.
  def plays_present(listed)
    present = listed.distinct.pluck(:format, :game_format)
    Event::PLAYS & present.map { |format, game| format == "multiplayer" ? format : game }
  end

  def average_fair_rate(seating)
    (@rounds.values.sum { |block| block[seating]["fair_rate"] } / @rounds.size).round(1)
  end

  # Up to nine admin-featured circuits (an ECL season, a championship) on a rail under the featured tournaments,
  # the waiting-list form and the choices of the floating filter bar.
  def load_extras
    @featured_circuits = Features.on?(:circuits) ? featured_circuits : []
    @waitlist_signup = WaitlistSignup.new
    @filter_options = ticket_filter_options
  end

  def featured_circuits
    Circuit.featured.with_attached_banner.preload(event_organizer: :user).order(:created_at)
      .limit(FEATURED_CIRCUITS_LIMIT).to_a
  end

  # One preload, the latest published rounds and one count for the featured and the upcoming tickets together.
  def ticket_counts(events)
    associations = [{ cover_attachment: :blob }, { event_organizer: { user: { avatar_attachment: :blob } } }]
    # The covers and the organizers' pictures are one attachments query each: alike enough to read as an N+1.
    Prosopite.pause
    ActiveRecord::Associations::Preloader.new(records: events, associations: associations).call
    Prosopite.resume
    Event.load_latest_published_round_numbers(events)
    EventParticipant.enrolled.where(event_id: events.map(&:id)).group(:event_id).count
  end
end
