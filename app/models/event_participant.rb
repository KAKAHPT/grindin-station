# frozen_string_literal: true

# The tournament representation of a player
class EventParticipant < ApplicationRecord
  belongs_to :event, counter_cache: true
  belongs_to :player

  # Scoring reads current results only; superseded rows (corrections to closed rounds) are audit.
  has_many :results, -> { publishable.current }, dependent: nil, inverse_of: :event_participant
  has_many :all_results, class_name: "Result", dependent: :destroy, inverse_of: :event_participant
  has_many :seatings, -> { publishable }, dependent: :destroy
  has_many :pods, -> { publishable }, through: :seatings
  has_many(
    :opponents,
    lambda { |event_participant|
      where.not(event_participants: { id: event_participant.id })
      .where(
        <<~SQL.squish
          pods.id not in (
            select pods.id
            from pods
            inner join rounds on pods.round_id = rounds.id
            where rounds.type = 'SingleEliminationRound'
          )
        SQL
      )
    }, class_name: "EventParticipant", through: :pods, source: :event_participants
  )

  DROP_REASONS = %w[drop no_show].freeze

  scope :playing, -> { where(dropped: false) }
  # Playing and holding a place: counted against the cap and paired.
  scope :enrolled, -> { playing.where(waitlisted: false) }
  scope :waitlist, -> { playing.where(waitlisted: true).order(:waitlist_position) }
  scope :not_eliminated, lambda {
    where(
      <<~SQL.squish
        not exists (
          select 1
          from results
          where results.event_participant_id = event_participants.id
            and results.type = 'Eliminated'
            and results.superseded_by_id is null
        )
      SQL
    )
  }

  attribute :rank, :integer
  attribute :player_email, :string
  attribute :player_name, :string
  attribute :accepted_terms, :boolean, default: false
  validates :drop_reason, inclusion: { in: DROP_REASONS }, allow_nil: true
  validate on: :create do
    errors.add(:accepted_terms, "Must accept the terms and conditions") unless accepted_terms?
  end

  before_validation on: :create do
    if player_email.present? && player.blank?
      user =
        User.find_or_create_by(email_address: player_email) do |u|
          u.name = player_name
          u.password = SecureRandom.hex(8)
        end

      self.player = user.player
    end
  end

  delegate :name, to: :player

  before_save :reset_rank_score_cache, if: -> { league_score_previously_changed? }
  before_save :stamp_check_in, if: -> { checked_in_changed? }
  before_save :stamp_drop, if: -> { dropped_changed? }
  after_update :rebuild_round, if: -> { dropped_previously_changed? }

  def initialize(attributes = nil)
    clear_standings_cache
    super
  end

  def number_of_infractions
    player.infractions.count { |p| p.event_id == event_id }
  end

  def playing?
    !dropped
  end

  def enrolled?
    playing? && !waitlisted?
  end

  # Roster filter states: enrolled, checked_in, waitlisted, dropped.
  def roster_status?(status)
    case status
    when "enrolled" then enrolled?
    when "checked_in" then enrolled? && checked_in?
    when "waitlisted" then playing? && waitlisted?
    when "dropped" then dropped?
    end
  end

  # Takes a place off the waitlist (the caller renumbers the rest).
  def promote!
    update!(waitlisted: false, waitlist_position: nil)
  end

  # The decklist field as commander text for public pages and feeds; nil when blank or a web address,
  # so a decklist link never goes public before the event allows it.
  def commander_text
    text = decklist.to_s.strip
    text unless text.empty? || text.match?(%r{\A(https?://|www\.|[a-z0-9-]+\.[a-z]{2,}(/|\z))}i)
  end

  def obfuscated_key
    "##{player.key.first(5)}"
  end

  # Times this participant sat at each position 1..5 in swiss rounds that are finished or published.
  # Byes have no seating, so they never count.
  def seat_counts
    return @standings.seat_counts(id) if @standings

    self.class.seat_counts_for(event, participant_ids: [id]).fetch(id) { self.class.empty_seat_counts }
  end

  # { participant id => { position => times } } for the whole event (or the given participants) in one query.
  # Empty for 1v1 events: their seats are random and never shown.
  def self.seat_counts_for(event, participant_ids: nil)
    return {} if event.one_v_one?

    scope = Seating.joins(pod: :round).where(rounds: { event_id: event.id, type: "SwissRound" })
      .where("rounds.finished_at IS NOT NULL OR rounds.published = TRUE")
    scope = scope.where(event_participant_id: participant_ids) if participant_ids
    scope.group(:event_participant_id, :order).count.each_with_object({}) do |((participant_id, position), times), all|
      (all[participant_id] ||= empty_seat_counts)[position] = times
    end
  end

  def self.empty_seat_counts = (1..5).index_with(0)

  # The event's participants loaded for the standings: players, current results with their rounds,
  # seat counts and swiss tables come in a fixed number of queries, whatever the field size.
  def self.standings_for(event)
    participants = event.event_participants.includes(:event, player: :user, results: :round).to_a
    standings = Standings.new(event, participants)
    participants.each { |participant| participant.standings = standings }
  end

  # Shared by the participants of one standings load (see .standings_for).
  class Standings
    def initialize(event, participants)
      @event = event
      @by_id = participants.index_by(&:id)
      @seat_counts = EventParticipant.seat_counts_for(event)
      index_tables(event)
    end

    def seat_counts(id) = @seat_counts.fetch(id) { EventParticipant.empty_seat_counts }

    # Loaded on first use, in one query for the whole field.
    def movement(id) = (@movements ||= StandingsSnapshot.movements_for(@event))[id]

    # One entry per shared closed non-cut table, like EventParticipant#opponents.
    def opponents(id)
      @tables[id].flat_map { |pod_id, _| @members[pod_id] - [id] }.filter_map { |other| @by_id[other] }
    end

    # Distinct players seated with the participant at the tables of the given rounds.
    def table_mates(id, round_ids)
      @tables[id].select { |_, round_id| round_ids.include?(round_id) }
        .flat_map { |pod_id, _| @members[pod_id] - [id] }.uniq.size
    end

    private

    def index_tables(event)
      @tables = Hash.new { |hash, key| hash[key] = [] } # participant id => [[pod id, round id], ...]
      @members = Hash.new { |hash, key| hash[key] = [] } # pod id => [participant id, ...]
      swiss_seatings(event).each do |pod_id, round_id, participant_id|
        @tables[participant_id] << [pod_id, round_id]
        @members[pod_id] << participant_id
      end
    end

    def swiss_seatings(event)
      Seating.joins(pod: :round).where(rounds: { event_id: event.id }).where.not(rounds: { finished_at: nil })
        .where.not(rounds: { type: "SingleEliminationRound" }).pluck(:pod_id, "pods.round_id", :event_participant_id)
    end
  end

  attr_writer :standings

  # Places moved between the two latest closed swiss rounds (positive = up); nil before round 2 closes,
  # once the swiss is over, or for someone missing from either snapshot.
  def movement_since_last_round
    @standings ? @standings.movement(id) : StandingsSnapshot.movements_for(event)[id]
  end

  def played_against?(another)
    opponents.include?(another)
  end

  # Advance results in single-elimination rounds (byes into the next cut round).
  def number_of_advancements
    results.count { |result| result.is_a?(Advance) && result.round.is_a?(SingleEliminationRound) }
  end

  # Advance results in swiss rounds: a bye, worth event.points_bye.
  def number_of_byes
    results.count { |result| result.is_a?(Advance) && result.round.is_a?(SwissRound) }
  end

  def number_of_draws
    results.count { |result| result.is_a?(Draw) }
  end

  def number_of_wins
    results.count { |result| result.is_a?(Win) }
  end

  def number_of_losses
    results.count { |result| result.is_a?(Loss) || result.is_a?(Penalty) }
  end

  # Share of real games won: wins / (wins + losses + draws). Byes (Advance) count in neither; nil before any game.
  def win_rate
    games = number_of_wins + number_of_losses + number_of_draws
    games.zero? ? nil : number_of_wins.fdiv(games)
  end

  def match_points # rubocop:disable Metrics/AbcSize -- one term per result type
    @match_points ||= (number_of_draws * event.points_draw) +
                      (number_of_wins * event.points_win) +
                      (number_of_losses * event.points_loss) +
                      (number_of_byes * event.points_bye)
  end

  # Swiss rounds the player got points from: games plus byes (a bye is worth a round). 1v1 counts only
  # swiss penalties, so a penalty in the cut cannot move the swiss seed the bracket is built from.
  def number_of_rounds_played
    losses = event.one_v_one? ? number_of_swiss_losses : number_of_losses
    number_of_wins + number_of_draws + losses + number_of_byes
  end

  # Penalty is a Loss subclass, so this is every loss row (penalties included) of a swiss round.
  def number_of_swiss_losses
    results.count { |result| result.is_a?(Loss) && result.round.is_a?(SwissRound) }
  end

  # Average over swiss pairings (byes and the top cut excluded) of each opponent's points out of
  # their maximum, each term floored at a draw. 0.0 without opponents.
  def opponents_win_rate # rubocop:disable Metrics/AbcSize
    @opponents_win_rate ||=
      begin
        floor = event.points_draw.to_f / event.points_win
        rates =
          opponent_records.map do |opponent|
            rounds = opponent.number_of_rounds_played
            rounds.zero? ? floor : [opponent.match_points / (rounds * event.points_win).to_f, floor].max
          end
        rates.empty? ? 0.0 : rates.sum / rates.size
      end
  end

  # MTR floor for every 1v1 win rate.
  RATE_FLOOR = 0.33

  # 1v1: match points out of the maximum for the rounds played (byes count), floored at 0.33.
  def match_win_rate
    @match_win_rate ||=
      begin
        rounds = number_of_rounds_played
        rounds.zero? ? RATE_FLOOR : [match_points.fdiv(rounds * event.points_win), RATE_FLOOR].max
      end
  end

  # 1v1: game points (3/1/0) out of 3 per game played over the swiss rounds; floored at 0.33. A bye counts
  # 2-0 through its own row (the pairer writes the Advance with games_won: 2).
  def game_win_rate
    @game_win_rate ||=
      begin
        swiss = results.select { |result| result.round.is_a?(SwissRound) }
        points = swiss.sum(&:game_points)
        played = swiss.sum { |result| result.games.sum }
        played.zero? ? RATE_FLOOR : [points.fdiv(3 * played), RATE_FLOOR].max
      end
  end

  # 1v1: average of the opponents' floored match win rates (byes excluded); 0.33 without opponents.
  def opponents_match_win_rate
    @opponents_match_win_rate ||= average_rate(opponent_records, :match_win_rate)
  end

  # 1v1: average of the opponents' floored game win rates (byes excluded); 0.33 without opponents.
  def opponents_game_win_rate
    @opponents_game_win_rate ||= average_rate(opponent_records, :game_win_rate)
  end

  # Distinct players at the swiss tables this participant won.
  def opponents_beaten
    @opponents_beaten ||=
      begin
        won_round_ids = results.select do |result|
          result.is_a?(Win) && result.round.is_a?(SwissRound)
        end.map(&:round_id)
        @standings ? @standings.table_mates(id, won_round_ids) : beaten_at(won_round_ids)
      end
  end

  # Distinct players faced in swiss rounds.
  def unique_opponents
    @unique_opponents ||= @standings ? opponent_records.map(&:id).uniq.size : opponents.distinct.count
  end

  # #opponents, from the shared standings load when there is one.
  def opponent_records
    @standings ? @standings.opponents(id) : opponents
  end

  # Last tiebreaker: a fixed draw per participant, reproducible from the event's seed.
  def tiebreak_salt
    Digest::MD5.hexdigest("#{event.seed}-#{id}").to_i(16) % 10_000
  end

  # Points, then opponents' win rate, then opponents beaten, then unique opponents, then the seeded salt.
  # Top cut advancements outrank everything.
  def rank_score # rubocop:disable Metrics/AbcSize,Metrics/MethodLength -- one term per tiebreaker
    @rank_score ||=
      if event.is_a?(League)
        league_score.to_f
      elsif event.one_v_one?
        one_v_one_score
      else
        (number_of_advancements * (10**18)) +
          (match_points * (10**13)) +
          ((opponents_win_rate * 10_000).round * (10**8)) +
          (opponents_beaten * (10**6)) +
          (unique_opponents * (10**4)) +
          tiebreak_salt
      end
  end

  # 1v1 rank score without the top cut advancements: the swiss seed the bracket was built from.
  def one_v_one_seed_score # rubocop:disable Metrics/AbcSize -- one term per tiebreaker
    (match_points * (10**17)) +
      ((opponents_match_win_rate * 10_000).round * (10**12)) + ((game_win_rate * 10_000).round * (10**8)) +
      ((opponents_game_win_rate * 10_000).round * (10**4)) + tiebreak_salt
  end

  # The readable tiebreakers, for the standings views.
  def standing_columns
    if event.one_v_one?
      return { points: match_points, omw: opponents_match_win_rate, gw: game_win_rate,
               ogw: opponents_game_win_rate }
    end

    { points: match_points, owr: opponents_win_rate, beaten: opponents_beaten,
      unique: unique_opponents, seats: seat_counts }
  end

  def reload(*)
    clear_standings_cache
    @standings = nil
    super
  end

  def rebuild_round
    latest = event.rounds.max_by(&:number)
    return unless event.swiss? && latest && !latest.published

    latest.destroy
    Tournaments::StartSwissRoundJob.perform_now(event.reload)
  end

  private

  # Advancements outrank the seed score (points, OMW, GW, OGW, then the salt).
  def one_v_one_score = (number_of_advancements * (10**21)) + one_v_one_seed_score

  def average_rate(records, rate)
    return RATE_FLOOR if records.empty?

    records.sum(&rate).fdiv(records.size)
  end

  def beaten_at(round_ids)
    won_pod_ids = pods.where(pods: { round_id: round_ids }).pluck("pods.id")
    Seating.where(pod_id: won_pod_ids).where.not(event_participant_id: id).distinct.count(:event_participant_id)
  end

  def stamp_check_in
    self.checked_in_at = checked_in ? Time.current : nil
  end

  def stamp_drop
    if dropped
      self.dropped_at ||= Time.current
      self.drop_reason ||= "drop"
    else
      self.dropped_at = nil
      self.drop_reason = nil
    end
  end

  def reset_rank_score_cache
    @rank_score = nil
  end

  def clear_standings_cache
    @match_points = nil
    @opponents_win_rate = nil
    @match_win_rate = nil
    @game_win_rate = nil
    @opponents_match_win_rate = nil
    @opponents_game_win_rate = nil
    @opponents_beaten = nil
    @unique_opponents = nil
    @rank_score = nil
  end
end
