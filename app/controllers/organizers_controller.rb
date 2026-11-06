# frozen_string_literal: true

# An organizer's public page (/o/:handle): who they are and every public event they run, current or upcoming
# first, then the past ones. The handle is the organizer user's; a user without an organizer, or an anonymised
# one, answers 404.
class OrganizersController < ApplicationController
  include EventTickets

  allow_unauthenticated_access

  before_action :set_organizer, only: :show

  # /organizers: every organizer with a public handle, A–Z, with their public event count and next event;
  # filtered by name (q) and country.
  def index
    read_filters
    @organizers = listed_organizers
    @countries = organizer_countries
    @events_counts = public_events.where(event_organizer_id: @organizers.map(&:id)).group(:event_organizer_id).count
    @next_events = next_events(@organizers.map(&:id))
  end

  def show
    @upcoming = current_or_upcoming
    @past = past_page
    @events_count = visible_events.count
    @enrolled = enrolled_counts(@upcoming + @past.to_a)
  end

  private

  def listed_organizers
    scope = EventOrganizer.joins(:user).includes(user: { avatar_attachment: :blob })
      .where(users: { anonymized_at: nil }).where.not(users: { handle: nil })
      .order(Arel.sql("LOWER(users.name)"))
    scope = scope.where(User.arel_table[:name].matches("%#{ActiveRecord::Base.sanitize_sql_like(@q)}%")) if @q.present?
    scope = scope.where(users: { country: @country }) if @country
    scope.to_a
  end

  def read_filters
    @q = params[:q].to_s.strip
    @country = params[:country].to_s.strip.upcase.presence
  end

  def organizer_countries
    EventOrganizer.joins(:user).where(users: { anonymized_at: nil }).where.not(users: { country: nil })
      .distinct.pluck("users.country").sort
  end

  # The first current or upcoming public event of each listed organizer, by id.
  def next_events(ids)
    public_events.where(event_organizer_id: ids, end_time: Time.current..).order(:start_time)
      .group_by(&:event_organizer_id).transform_values(&:first)
  end

  def set_organizer
    @user = User.find_by(handle: params.expect(:handle))
    @organizer = @user&.event_organizer
    raise ActiveRecord::RecordNotFound unless @organizer && !@user.anonymized?
  end

  def current_or_upcoming = ticket_preload(visible_events.where(end_time: Time.current..).order(:start_time)).to_a

  def past_page = ticket_preload(visible_events.past.order(start_time: :desc)).page(params[:page]).load

  # Tournaments and leagues in one query: the state enum lives on the subclasses, and both map the hidden states
  # (draft, canceled) to the same integers, so the base class can filter them by value.
  def visible_events = public_events.where(event_organizer: @organizer)

  def public_events = Event.where.not(state: Tournament.states.values_at(*Event::HIDDEN_STATES))
end
