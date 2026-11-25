# frozen_string_literal: true

class League < Event
  paginates_per 20

  # open_tables: the players open and fill their own tables (the default for a new league); pickup: the
  # organizer creates each pod; scheduled: rounds on a calendar (not built).
  enum :play_mode, { scheduled: 0, pickup: 1, open_tables: 2 }, prefix: true

  TABLE_SIZE = 4
  # A table that has not filled this long after it was opened closes by itself.
  TABLE_WAIT = 2.hours
  DRAW_RULES = %w[split lost].freeze
  CUT_SIZES = [0, 4, 16].freeze

  # What a new league starts with; rows already stored keep their values.
  attribute :play_mode, default: 2
  attribute :result_confirmation, default: "one"
  attribute :confirmation_timeout_minutes, default: 1440
  attribute :top_cut_size, default: 16

  has_many :league_tables, foreign_key: :event_id, dependent: :destroy, inverse_of: :league

  # Leagues pair pods of 3-5; the 1v1 pairer and bracket are tournament-only.
  validates :format, inclusion: { in: %w[multiplayer] }
  validates :wager_percentage,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100, allow_blank: true }
  validates :starting_points, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :draw_rule, inclusion: { in: DRAW_RULES }
  validates :min_games_for_cut, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :max_games_per_week, :max_games_vs_same_opponent,
            numericality: { only_integer: true, greater_than_or_equal_to: 1 }, allow_nil: true
  validates :top_cut_size, inclusion: { in: CUT_SIZES }, allow_nil: true

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

  alias pickup_play_mode? play_mode_pickup?

  def rounds_info
    {
      rounds: [{ swiss_round: :standard }, { swiss_round: :standard }, { swiss_round: :standard }],
      top: { players: 3, pods: [1] }
    }
  end

  def perform_state_based_actions
    return unless TRANSITIONS[state_previously_was.to_sym].include?(state.to_sym)

    case state.to_sym
    when :play
      Leagues::StartPlayRoundJob.perform_now(self)
    when :finals
      Leagues::StartFinalsRoundJob.perform_now(self)
    when :finished
      Leagues::FinishLeagueJob.perform_now(self)
    end
  end
end
