# frozen_string_literal: true

class Tournament < Event
  paginates_per 20

  scope :ongoing, -> { where(state: %i[swiss single_elimination]) }

  # Default points per result; each event keeps its own (events.points_*), editable until the swiss starts.
  POINTS_PER_WIN = 7
  POINTS_PER_LOSS = 0
  POINTS_PER_DRAW = 1
  POINTS_PER_BYE = POINTS_PER_WIN

  enum :state, {
    draft: 0,
    registration_open: 1,
    registration_closed: 2,
    swiss: 3,
    single_elimination: 4,
    finished: 5,
    canceled: 6
  }, default: :registration_open

  TRANSITIONS = {
    draft: %i[draft registration_open registration_closed],
    registration_open: %i[registration_open registration_closed canceled],
    registration_closed: %i[registration_closed swiss canceled],
    swiss: %i[single_elimination finished canceled],
    single_elimination: %i[finished canceled],
    finished: [:finished],
    canceled: [:canceled]
  }.with_indifferent_access.freeze

  # States from which the top cut must fit the field (players can no longer register).
  TOP_CUT_CHECKED_STATES = %w[registration_closed swiss single_elimination finished].freeze

  validates :top_cut_size, inclusion: { in: [0] + Tournaments::TopCut::SIZES }, allow_nil: true
  validates :swiss_rounds_count, numericality: { only_integer: true, greater_than_or_equal_to: 1 }, allow_nil: true
  validates :round_minutes, :top_cut_round_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  STRUCTURE_ATTRIBUTES = %i[swiss_rounds_count top_cut_size round_minutes top_cut_round_minutes].freeze

  validate :top_cut_fits_the_field
  validate :structure_locked_after_start, on: :update
  before_update :snapshot_structure, if: -> { will_save_change_to_state? && swiss? }

  def suggested_structure
    Tournaments::Structure.suggested(playing_participants_count)
  end

  def rounds_info
    total = swiss_rounds_count || suggested_structure[:swiss_rounds]
    cut_size = top_cut_size || suggested_structure[:top_cut_size]
    cut = Tournaments::TopCut.for(cut_size) if cut_size.positive?

    {
      rounds: (1..total).map { |number| { swiss_round: swiss_round_strategy(number, total) } },
      top: cut && { players: cut.players, pods: cut.stages.pluck(:pods) }
    }
  end

  # Without a top cut there is no single elimination stage to move to.
  def available_states = rounds_info[:top] ? super : super.except(:single_elimination)

  def progress_percent
    total_rounds = number_of_swiss_rounds + number_of_single_elimination_rounds
    return 0 if total_rounds.zero?

    (rounds.finished.count.to_f / total_rounds) * 100
  end

  def number_of_swiss_rounds
    rounds_info[:rounds]&.size || 0
  end

  def number_of_single_elimination_rounds
    rounds_info.dig(:top, :pods)&.size || 0
  end

  def single_elimination_round_name(round_number)
    %w[Finals Semi-Finals Quarter-Finals][number_of_swiss_rounds + number_of_single_elimination_rounds - round_number]
  end

  def ongoing?
    %w[swiss single_elimination].include?(state)
  end

  def perform_state_based_actions
    return unless TRANSITIONS[state_previously_was.to_sym].include?(state.to_sym)

    case state.to_sym
    when :swiss
      Tournaments::StartSwissRoundJob.perform_now(self)
    when :single_elimination
      Tournaments::StartSingleEliminationRoundJob.perform_now(self)
    when :finished
      Tournaments::FinishTournamentJob.perform_now(self)
    end
  end

  private

  def swiss_round_strategy(number, total)
    if number == 2 && total >= 3 then :spread
    elsif number == total && total >= 4 then :forced
    else :standard
    end
  end

  def structure_locked_after_start
    return unless points_locked?

    STRUCTURE_ATTRIBUTES.each do |attribute|
      errors.add(attribute, :locked) if attribute_changed?(attribute)
    end
  end

  # A nil structure follows the player count; freeze it when the swiss starts so drops can't change it mid-event.
  # The seed for fair-seating tie-breaks is drawn at the same moment.
  def snapshot_structure
    suggested = suggested_structure
    self.swiss_rounds_count ||= suggested[:swiss_rounds]
    self.top_cut_size ||= suggested[:top_cut_size]
    self.seed ||= SecureRandom.random_number(2**31)
  end

  def top_cut_fits_the_field
    return unless top_cut_size.to_i.positive? && TOP_CUT_CHECKED_STATES.include?(state)
    return unless Tournaments::TopCut::SIZES.include?(top_cut_size)

    participants = playing_participants_count
    return if participants.zero? || Tournaments::TopCut.for(top_cut_size).valid_for?(participants)

    errors.add(:top_cut_size, :too_big)
  end
end
