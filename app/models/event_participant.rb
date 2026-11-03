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

  def obfuscated_key
    "##{player.key.first(5)}"
  end

  # Times this participant sat at each position 1..5 in swiss rounds that are finished or published.
  # Byes have no seating, so they never count.
  def seat_counts
    counts = Seating.joins(pod: :round)
      .where(event_participant_id: id, rounds: { type: "SwissRound" })
      .where("rounds.finished_at IS NOT NULL OR rounds.published = TRUE")
      .group(:order).count
    (1..5).index_with { |position| counts.fetch(position, 0) }
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

  # Swiss rounds the player got points from: games plus byes (a bye is worth a round).
  def number_of_rounds_played
    number_of_wins + number_of_draws + number_of_losses + number_of_byes
  end

  # Average over swiss pairings (byes and the top cut excluded) of each opponent's points out of
  # their maximum, each term floored at a draw. 0.0 without opponents.
  def opponents_win_rate # rubocop:disable Metrics/AbcSize
    @opponents_win_rate ||=
      begin
        floor = event.points_draw.to_f / event.points_win
        rates =
          opponents.map do |opponent|
            rounds = opponent.number_of_rounds_played
            rounds.zero? ? floor : [opponent.match_points / (rounds * event.points_win).to_f, floor].max
          end
        rates.empty? ? 0.0 : rates.sum / rates.size
      end
  end

  # Distinct players at the swiss tables this participant won.
  def opponents_beaten
    @opponents_beaten ||=
      begin
        won_round_ids = results.select do |result|
          result.is_a?(Win) && result.round.is_a?(SwissRound)
        end.map(&:round_id)
        won_pod_ids = pods.where(pods: { round_id: won_round_ids }).pluck("pods.id")
        Seating.where(pod_id: won_pod_ids).where.not(event_participant_id: id).distinct.count(:event_participant_id)
      end
  end

  # Distinct players faced in swiss rounds.
  def unique_opponents
    @unique_opponents ||= opponents.distinct.count
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
      else
        (number_of_advancements * (10**18)) +
          (match_points * (10**13)) +
          ((opponents_win_rate * 10_000).round * (10**8)) +
          (opponents_beaten * (10**6)) +
          (unique_opponents * (10**4)) +
          tiebreak_salt
      end
  end

  # The readable tiebreakers, for the standings views.
  def standing_columns
    { points: match_points, owr: opponents_win_rate, beaten: opponents_beaten,
      unique: unique_opponents, seats: seat_counts }
  end

  def reload(*)
    clear_standings_cache
    super
  end

  def rebuild_round
    latest = event.rounds.max_by(&:number)
    return unless event.swiss? && latest && !latest.published

    latest.destroy
    Tournaments::StartSwissRoundJob.perform_now(event.reload)
  end

  private

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
    @opponents_beaten = nil
    @unique_opponents = nil
    @rank_score = nil
  end
end
