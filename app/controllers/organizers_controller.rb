# frozen_string_literal: true

# An organizer's public page (/o/:handle): who they are and every public event they run, current or upcoming
# first, then the past ones. The handle is the organizer user's; a user without an organizer, or an anonymised
# one, answers 404.
class OrganizersController < ApplicationController
  include EventTickets

  allow_unauthenticated_access

  before_action :set_organizer

  def show
    @upcoming = current_or_upcoming
    @past = past_page
    @events_count = visible_events.count
    @enrolled = enrolled_counts(@upcoming + @past.to_a)
  end

  private

  def set_organizer
    @user = User.find_by(handle: params.expect(:handle))
    @organizer = @user&.event_organizer
    raise ActiveRecord::RecordNotFound unless @organizer && !@user.anonymized?
  end

  def current_or_upcoming = ticket_preload(visible_events.where(end_time: Time.current..).order(:start_time)).to_a

  def past_page = ticket_preload(visible_events.past.order(start_time: :desc)).page(params[:page]).load

  # Tournaments and leagues in one query: the state enum lives on the subclasses, and both map the hidden states
  # (draft, canceled) to the same integers, so the base class can filter them by value.
  def visible_events
    hidden = Tournament.states.values_at(*Event::HIDDEN_STATES)
    Event.where(event_organizer: @organizer).where.not(state: hidden)
  end
end
