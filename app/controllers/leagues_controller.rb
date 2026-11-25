# frozen_string_literal: true

class LeaguesController < ApplicationController
  include PublicEvent
  include EventTickets

  skip_before_action :require_authentication

  TABLE_PRELOAD = { participants: { player: :user },
                    pod: [{ round: :results }, { seatings: { event_participant: { player: :user } } }] }.freeze

  # Public leagues as tickets (upcoming by default, ?filter=past) and the viewer's own running now.
  def index
    @past = params[:filter] == "past"
    @ongoing = ongoing_tickets(League)
    @leagues = ticket_scope(League, past: @past, except: @ongoing)
    @enrolled = enrolled_counts(@leagues.to_a + @ongoing)
  end

  def show
    scope = League.preload(:rounds, cover_attachment: :blob, event_participants: [:results, { player: :user }])
    @league = ensure_public!(scope.find(params[:id]))
    return unless @league.play_mode_open_tables?

    @tab = params[:tab].presence_in(%w[tables standings]) || "about"
    @standings = @league.ranked_participants if @tab == "standings"
    load_tables if @tab == "tables"
  end

  private

  # The Tables tab: the viewer's own table, the tables waiting for players and the ones being played.
  def load_tables # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity -- three lists from one load
    tables = @league.league_tables.where(state: %w[waiting filled]).preload(TABLE_PRELOAD).order(:created_at).to_a
    @participant = current_user&.player && @league.event_participants.find_by(player: current_user.player)
    @my_table = @participant && tables.find { |table| mine?(table) }
    @waiting = tables.select { |table| table.waiting? && !table.overdue? } - [@my_table]
    @in_play = tables.select(&:in_play?) - [@my_table]
  end

  # Waiting with the viewer in it, or full with the viewer seated and no final result yet.
  def mine?(table)
    seated = table.participants.any? { |participant| participant.id == @participant.id }
    seated && (table.waiting? ? !table.overdue? : table.in_play?)
  end
end
