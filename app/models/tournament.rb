# frozen_string_literal: true

class Tournament < Event # rubocop:disable Metrics/ClassLength
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

  validates :top_cut_size, inclusion: { in: ->(t) { [0] + Tournaments::TopCut.sizes_for(t.format) } }, allow_nil: true
  # 0 swiss rounds (straight single elimination) only makes sense for 1v1
  validates :swiss_rounds_count, numericality: { only_integer: true, greater_than_or_equal_to: 1 }, allow_nil: true,
                                 unless: :one_v_one?
  validates :swiss_rounds_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true,
                                 if: :one_v_one?
  validates :round_minutes, :top_cut_round_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  STRUCTURE_ATTRIBUTES = %i[swiss_rounds_count top_cut_size round_minutes top_cut_round_minutes].freeze

  validate :top_cut_fits_the_field
  validate :structure_locked_after_start, on: :update
  before_update :snapshot_structure, if: lambda {
    will_save_change_to_state? && (swiss? || straight_to_single_elimination?)
  }

  def suggested_structure
    Tournaments::Structure.suggested(playing_participants_count, format: format)
  end

  def rounds_info
    total = swiss_rounds_count || suggested_structure[:swiss_rounds]
    cut_size = top_cut_size || suggested_structure[:top_cut_size]
    cut = Tournaments::TopCut.for(cut_size, format: format) if cut_size.positive?

    {
      rounds: (1..total).map { |number| { swiss_round: swiss_round_strategy(number, total) } },
      top: cut && { players: cut.players, pods: cut.stages.pluck(:pods) }
    }
  end

  # Without a top cut there is no single elimination stage to move to.
  def available_states
    top = rounds_info[:top]
    states = top ? super : super.except(:single_elimination)
    return states unless registration_closed? && no_swiss? && top

    states.except(:swiss).merge(self.class.states.slice(:single_elimination))
  end

  # The multiplayer map; a 1v1 with no swiss rounds goes registration_closed -> single_elimination instead of swiss.
  def transitions
    return TRANSITIONS unless no_swiss? && top_cut_size_or_suggested.positive?

    TRANSITIONS.merge(registration_closed: TRANSITIONS[:registration_closed] - [:swiss] + [:single_elimination])
  end

  def progress_percent
    finished = rounds.loaded? ? rounds.count(&:past?) : rounds.finished.count
    return 0 if finished.zero?

    total_rounds = number_of_swiss_rounds + number_of_single_elimination_rounds
    total_rounds.zero? ? 0 : (finished.to_f / total_rounds) * 100
  end

  def number_of_swiss_rounds
    rounds_info[:rounds]&.size || 0
  end

  def number_of_single_elimination_rounds
    rounds_info.dig(:top, :pods)&.size || 0
  end

  def single_elimination_round_name(round_number)
    names =
      if one_v_one?
        ["Finals", "Semifinals", "Quarterfinals", "Round of 16",
         "Round of 32"]
      else
        %w[Finals Semi-Finals Quarter-Finals]
      end
    names[number_of_swiss_rounds + number_of_single_elimination_rounds - round_number]
  end

  def ongoing?
    %w[swiss single_elimination].include?(state)
  end

  def perform_state_based_actions
    return unless transitions[state_previously_was.to_sym].include?(state.to_sym)

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

  def no_swiss? = one_v_one? && (swiss_rounds_count || suggested_structure[:swiss_rounds]).zero?

  def top_cut_size_or_suggested = top_cut_size || suggested_structure[:top_cut_size]

  def straight_to_single_elimination? = no_swiss? && single_elimination? && state_was == "registration_closed"

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
    return unless top_cut_size.to_i.positive? && top_cut_checked?
    return unless Tournaments::TopCut.sizes_for(format).include?(top_cut_size)

    participants = playing_participants_count
    return if participants.zero? || Tournaments::TopCut.for(top_cut_size, format: format).valid_for?(participants)

    errors.add(:top_cut_size, :too_big)
  end

  # The cut must fit the playing field while registration is closed and when the swiss starts; once it is
  # running the structure is locked, so later drops must not make the record invalid.
  def top_cut_checked?
    registration_closed? || ((swiss? || straight_to_single_elimination?) && will_save_change_to_state?)
  end
end
