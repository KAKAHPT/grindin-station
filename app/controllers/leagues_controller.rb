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

    @tab = params[:tab].presence_in(%w[tables mine played standings]) || "about"
    load_me
    load_registration
    load_tab
  end

  private

  # The viewer's own strip beside the tabs: their entry, place in the standings and how many are ranked.
  def load_me
    @me = my_record or return

    @ranked = @league.ranked_participants
    @my_rank = @ranked.index { |participant| participant.id == @me.id }&.succ
    @ranked_count = @ranked.size
  end

  def load_tab
    case @tab
    when "standings" then @standings = final_order(@ranked || @league.ranked_participants)
    when "tables", "mine" then load_tables
    when "played" then load_played
    end
  end

  # A finished league reads in its final order (the cut's champion first), not by score.
  def final_order(ranked)
    return ranked unless @league.finished?

    ranked.sort_by.with_index { |participant, index| [participant.final_position || Float::INFINITY, index] }
  end

  # The viewer's registration (enrolled, waitlisted or dropped), for the sign-up card.
  def load_registration
    @registration = current_user&.player && @league.event_participants.find do |p|
      p.player_id == current_user.player.id
    end
  end

  # The signed-in player's own entry in the league, for the strip beside the tabs (picture, record, win rate).
  def my_record
    player = current_user&.player or return

    @league.event_participants.find do |participant|
      participant.player_id == player.id && participant.enrolled?
    end
  end

  # The Tables tab: the viewer's own table, the tables waiting for players and the ones being played.
  def load_tables # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity -- three lists from one load
    tables = @league.league_tables.where(state: %w[waiting filled]).preload(TABLE_PRELOAD).order(:created_at).to_a
    @participant = current_user&.player && @league.event_participants.find_by(player: current_user.player)
    @my_table = @participant && tables.find { |table| mine?(table) }
    @waiting = tables.select { |table| table.waiting? && !table.overdue? }
    @in_play = tables.select(&:in_play?)
    load_my_games if @tab == "mine" && @participant
    load_cut if @league.finals? || @league.finished?
  end

  # My round: the viewer's own finished league games, latest first.
  def load_my_games
    @my_games = @league.league_tables.filled.joins(:seats, pod: :round)
      .where(league_table_seats: { event_participant_id: @participant.id }).where.not(rounds: { finished_at: nil })
      .order("rounds.finished_at DESC").preload(TABLE_PRELOAD).limit(20).to_a
  end

  # The top cut's rounds, latest first, and the viewer's own table still to finish in the round being played.
  def load_cut
    @cut_rounds = LeagueCutRound.where(event: @league).order(number: :desc)
      .preload(:results, pods: { seatings: { event_participant: { player: :user } } }).to_a
    round = @cut_rounds.find { |cut| cut.finished_at.nil? }
    @my_cut_round = round
    @my_cut_pod = @participant && round&.pods&.find { |pod| cut_seat_open?(round, pod) }
  end

  def cut_seat_open?(round, pod)
    seated = pod.seatings.map(&:event_participant_id)
    seated.include?(@participant.id) && round.results.none? { |result| seated.include?(result.event_participant_id) }
  end

  # The Completed rounds tab: the games with a final result, latest first.
  def load_played # rubocop:disable Metrics/AbcSize
    @participant = current_user&.player && @league.event_participants.find_by(player: current_user.player)
    @played = @league.league_tables.filled.joins(pod: :round).where.not(rounds: { finished_at: nil })
      .order("rounds.finished_at DESC").preload(TABLE_PRELOAD).page(params[:page]).per(24)
  end

  # Waiting with the viewer in it, or full with the viewer seated and no final result yet.
  def mine?(table)
    seated = table.participants.any? { |participant| participant.id == @participant.id }
    seated && (table.waiting? ? !table.overdue? : table.in_play?)
  end
end
