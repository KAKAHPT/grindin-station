# frozen_string_literal: true

class League < Event
  paginates_per 20

  # open_tables: the players open and fill their own tables (the default for a new league); pickup: the
  # organizer creates each pod; scheduled: rounds on a calendar (not built).
  enum :play_mode, { scheduled: 0, pickup: 1, open_tables: 2 }, prefix: true

  TABLE_SIZE = 4
  # A table that has not filled this long after it was opened closes by itself.
  TABLE_WAIT = 2.hours
  # With result_confirmation "one": a reported result nobody confirmed or said was wrong is accepted after this.
  CONFIRMATION_WINDOW = 24.hours
  # none: a report closes the game at once; one: another player of the table confirms it first.
  CONFIRMATIONS = %w[none one].freeze
  DRAW_RULES = %w[split lost].freeze
  CUT_SIZES = [0, 4, 16].freeze
  # The organizer-run modes (pickup, scheduled): three rounds and a final of the top 3, as before.
  LEGACY_ROUNDS = { rounds: [{ swiss_round: :standard }] * 3, top: { players: 3, pods: [1] } }.freeze

  # What a new league starts with; rows already stored keep their values.
  attribute :play_mode, default: 2
  # A reported result closes the game at once, unless the organizer asks for a confirmation (CONFIRMATIONS);
  # a mistake is fixed by a correction request to the staff.
  attribute :result_confirmation, default: "none"
  attribute :top_cut_size, default: 16
  attribute :wager_percentage, default: 10

  # Removed by the database with the league (and with a participant who is deleted).
  has_many :league_tables, foreign_key: :event_id, dependent: nil, inverse_of: :league

  # Leagues pair pods of 3-5; the 1v1 pairer and bracket are tournament-only.
  validates :format, inclusion: { in: %w[multiplayer] }
  validates :wager_percentage,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100, allow_blank: true }
  validates :wager_percentage, presence: true, if: :play_mode_open_tables?
  validates :starting_points, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :draw_rule, inclusion: { in: DRAW_RULES }
  validates :min_games_for_cut, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :max_games_per_week, :max_games_vs_same_opponent,
            numericality: { only_integer: true, greater_than_or_equal_to: 1 }, allow_nil: true
  validates :top_cut_size, inclusion: { in: CUT_SIZES }, allow_nil: true

  # Before the first game everyone shows the starting points, also when the organizer changes them.
  after_update :reset_scores, if: -> { saved_change_to_starting_points? && play_mode_open_tables? }

  enum :state, {
    draft: 0,
    registration_open: 1,
    registration_closed: 2,
    play: 3,
    finals: 4,
    finished: 5,
    canceled: 6,
    # closing: the organizer closed the league and the tables already full play to the end; closed: every
    # table is settled, the standings are frozen and the cut can be made.
    closing: 7,
    closed: 8
  }, default: :registration_open

  TRANSITIONS = {
    draft: %i[draft registration_open registration_closed],
    registration_open: %i[registration_open registration_closed play canceled],
    registration_closed: %i[registration_closed play canceled],
    play: %i[closing finals finished canceled],
    closing: %i[closed play canceled],
    closed: %i[finals finished play],
    finals: %i[finished canceled],
    finished: [:finished],
    canceled: [:canceled]
  }.with_indifferent_access.freeze

  scope :ongoing, -> { where(state: %i[play finals]) }

  def playing?
    state.in?(%w[play closing closed finals])
  end

  # Players can open and join tables: in play, in the open-tables mode, before the end date.
  def tables_open?
    play? && play_mode_open_tables? && (end_time.nil? || end_time.future?)
  end

  # An open-tables league keeps taking players while it is in play: a late one starts with the starting points.
  def accepts_registrations? = registration_open? || (play? && play_mode_open_tables?)

  alias pickup_play_mode? play_mode_pickup?

  # No planned rounds: the games come as the players open tables. The cut is the tournament one, of the
  # size stored when the organizer made it (top_cut_size).
  def rounds_info
    return LEGACY_ROUNDS unless play_mode_open_tables?

    cut = Tournaments::TopCut.for(top_cut_size) if top_cut_size.to_i.positive?
    { rounds: [], top: cut && { players: cut.players, pods: cut.stages.pluck(:pods) } }
  end

  # The cut rounds are numbered after the league's games, so the tournament cut code finds its stage.
  def number_of_swiss_rounds = rounds.where.not(type: "LeagueCutRound").maximum(:number).to_i

  def number_of_single_elimination_rounds = rounds_info[:top] ? rounds_info[:top][:pods].size : 0

  def single_elimination_round_name(round_number)
    remaining = number_of_swiss_rounds + number_of_single_elimination_rounds - round_number
    remaining.zero? ? I18n.t("rounds.cut_names.finals") : "Top #{top_cut_size}"
  end

  # The standings: league score, then more wins, then fewer games, then who registered first.
  def ranked_participants
    EventParticipant.standings_for(self).select(&:ranked?).sort_by do |participant|
      [-participant.league_score.to_d, -participant.number_of_wins, participant.league_games, participant.created_at]
    end
  end

  # Who can make the cut, in standings order: enrolled, with at least min_games_for_cut league games.
  def cut_field
    ranked_participants.select { |participant| participant.enrolled? && participant.league_games >= min_games_for_cut }
  end

  # The largest cut the qualified field fills: the chosen size, else 4, else none. No cut when none was chosen.
  def cut_size_for_field
    return 0 unless top_cut_size.to_i.positive?

    qualified = cut_field.size
    [top_cut_size.to_i, 4].uniq.find { |size| size.positive? && qualified >= size } || 0
  end

  def perform_state_based_actions
    return unless TRANSITIONS[state_previously_was.to_sym].include?(state.to_sym)

    case state.to_sym
    when :play then Leagues::StartPlayRoundJob.perform_now(self) unless play_mode_open_tables?
    when :finals then start_finals
    when :finished then Leagues::FinishLeagueJob.perform_now(self)
    end
  end

  private

  def reset_scores = Scoring::PointWager.new(self).recalculate_all!

  def start_finals
    return Leagues::StartFinalsRoundJob.perform_now(self) unless play_mode_open_tables?

    LeagueCutRound.start!(self, number_of_swiss_rounds + 1)
  end
end
