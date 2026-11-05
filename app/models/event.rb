# frozen_string_literal: true

class Event < ApplicationRecord # rubocop:disable Metrics/ClassLength
  belongs_to :circuit, optional: true
  belongs_to :event_organizer
  has_many :rounds, dependent: :destroy
  has_many :event_participants, dependent: :destroy
  has_many :infractions, dependent: :destroy
  has_many :rooms, dependent: :destroy
  has_many :pods, through: :rounds
  has_many :event_staff, class_name: "EventStaff", dependent: :destroy
  has_many :judge_calls, dependent: :destroy
  has_many :standings_snapshots, dependent: :delete_all

  PREFERRED_POD_SIZE = 4
  SMALLER_POD_SIZE = 3

  FORMATS = %w[multiplayer one_v_one].freeze
  PAIRING_MODES = %w[swiss power random].freeze
  UNEVEN_FIELDS = %w[pods_of_three byes].freeze
  MATCH_GAMES = [1, 3].freeze
  # Admin-only tier (M13 D16): invitational points = ranking points x multiplier; never shown publicly.
  TIERS = %w[none bronze silver gold platinum].freeze
  TIER_MULTIPLIERS = { "none" => 0, "bronze" => 1, "silver" => 1.5, "gold" => 2, "platinum" => 3 }.freeze
  # MTR match points for 1v1 events (win/draw/loss/bye); multiplayer keeps the column defaults.
  ONE_V_ONE_POINTS = { points_win: 3, points_draw: 1, points_loss: 0, points_bye: 3 }.freeze
  POINT_ATTRIBUTES = %i[points_win points_draw points_loss points_bye].freeze
  UNLOCKED_POINTS_STATES = %w[draft registration_open registration_closed].freeze
  RESULT_CONFIRMATIONS = %w[none one all].freeze
  TOP_CUT_TIMEOUT_RULES = %w[highest_seed_advances replay].freeze
  # A draft or canceled event exists only for its staff: hidden from public pages.
  HIDDEN_STATES = %w[draft canceled].freeze
  COVER_TYPES = %w[image/jpeg image/png image/webp].freeze
  COVER_MAX_SIZE = 4.megabytes

  scope :for_organizer, ->(organizer) { where(event_organizer: organizer) }
  # Events the user owns (through their EventOrganizer) or works as staff.
  scope :staffed_by, lambda { |user|
    staffed = where(id: EventStaff.where(user_id: user.id).select(:event_id))
    user.event_organizer ? for_organizer(user.event_organizer).or(staffed) : staffed
  }
  # On Tournament or League: state is their enum (the names do not cast on Event itself).
  scope :visible, -> { where.not(state: HIDDEN_STATES) }
  scope :past, -> { where(end_time: ...Time.current) }
  scope :upcoming, -> { where(start_time: Time.current..) }
  scope :for_player, ->(player) { joins(:event_participants).where(event_participants: { player: player }) }

  enum :currency, EventOrganizer::CURRENCIES

  has_one_attached :cover

  normalizes :country, with: ->(country) { country.strip.upcase.presence }

  with_options presence: true do
    validates :state, :name, :slug, :start_time, :end_time
  end

  validates :points_win, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :points_draw, :points_loss, :points_bye, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :points_locked_after_start, on: :update
  validate :valid_transition, on: :update, if: :will_save_change_to_state?
  validates :format, inclusion: { in: FORMATS }
  validates :match_games, inclusion: { in: MATCH_GAMES }
  validates :pairing_mode, inclusion: { in: PAIRING_MODES }
  validates :uneven_field, inclusion: { in: UNEVEN_FIELDS }
  validates :tier, inclusion: { in: TIERS }
  validates :country, format: { with: /\A[A-Z]{2}\z/ }, allow_nil: true
  validate :format_locked_after_creation, on: :update
  validates :result_confirmation, inclusion: { in: RESULT_CONFIRMATIONS }
  validates :top_cut_timeout_rule, inclusion: { in: TOP_CUT_TIMEOUT_RULES }
  validates :confirmation_timeout_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 1 }

  validates :slug, uniqueness: true
  validate :circuit_of_the_same_organizer, if: :will_save_change_to_circuit_id?
  validate :cover_type_and_size
  # Points not given for a new 1v1 event start at the MTR values instead of the multiplayer defaults.
  after_initialize :apply_one_v_one_points, if: :new_record?
  before_validation :populate_slug, if: -> { slug.blank? }
  before_validation { self.pairing_mode = "swiss" if one_v_one? } # 1v1 never pairs by mode (spec M8 §1)
  before_validation { self.uneven_field = "pods_of_three" if one_v_one? } # 1v1 pairs 2-player pods only
  # The country filter on /events (M13 D12): a new event starts in its organizer's country.
  before_validation(on: :create) { self.country = event_organizer&.user&.country if country.blank? }

  after_update :perform_state_based_actions, if: -> { state_previously_changed? }
  after_save :geocode_address, if: -> { address_previously_changed? }

  # read_attribute: a record loaded against a schema without the column (or a stale schema cache) would otherwise
  # fall through to Kernel#format and raise "too few arguments".
  def one_v_one? = self[:format] == "one_v_one"

  def multiplayer? = self[:format] == "multiplayer"

  def swiss_pairing? = pairing_mode == "swiss"

  def power_pairing? = pairing_mode == "power"

  def random_pairing? = pairing_mode == "random"

  def pods_of_three? = uneven_field == "pods_of_three"

  def byes? = uneven_field == "byes"

  # Locked in the state being saved or the one it leaves, so a state change cannot unlock them.
  def points_locked?
    UNLOCKED_POINTS_STATES.exclude?(state) || (persisted? && UNLOCKED_POINTS_STATES.exclude?(state_was))
  end

  # The state machine: Tournament adapts it for a 1v1 with no swiss.
  def transitions
    self.class::TRANSITIONS
  end

  # Registered players who have not dropped and are off the waitlist (from the loaded association when there is one).
  def playing_participants_count
    event_participants.loaded? ? event_participants.count(&:enrolled?) : event_participants.enrolled.count
  end

  # A finite maximum reached by the enrolled players; enrolled is passed when the count is already known.
  def sold_out?(enrolled = playing_participants_count)
    maximum_participants.finite? && enrolled >= maximum_participants
  end

  def promote_from_waitlist!(participant)
    with_lock do
      participant.promote!
      renumber_waitlist!
    end
  end

  # After a place is freed (freed_place) the first on the waitlist takes it; positions are then closed up.
  def fill_from_waitlist!(freed_place:)
    event_participants.waitlist.first&.promote! if freed_place
    renumber_waitlist!
  end

  # Closes the gaps in the waitlist positions: 1, 2, 3...
  def renumber_waitlist!
    event_participants.waitlist.each.with_index(1) do |participant, position|
      participant.update!(waitlist_position: position) unless participant.waitlist_position == position
    end
  end

  # The latest published round's number (nil before round 1 is published); the ticket lists set it for a whole
  # page in one query (Event.load_latest_published_round_numbers).
  attr_writer :latest_published_round_number

  def latest_published_round_number
    return @latest_published_round_number if defined?(@latest_published_round_number)

    @latest_published_round_number = rounds.published.maximum(:number)
  end

  def self.load_latest_published_round_numbers(events)
    numbers = Round.published.where(event_id: events.map(&:id)).group(:event_id).maximum(:number)
    events.each { |event| event.latest_published_round_number = numbers[event.id] }
  end

  def available_states
    return self.class.states.slice(:draft) if new_record?

    self.class.states.slice(*(self.class::TRANSITIONS[state] - [state.to_sym]))
  end

  def geocode_address
    Events::GeocodeJob.perform_later(self)
  end

  def latitude=(latitude)
    self.location = RGeo::Geographic
      .spherical_factory(srid: 4326)
      .point(longitude, latitude)
  end

  def longitude=(longitude)
    self.location = RGeo::Geographic
      .spherical_factory(srid: 4326)
      .point(longitude, latitude)
  end

  def latitude
    location&.y || 0
  end

  def longitude
    location&.x || 0
  end

  def minimum_participants=(num_players)
    self.participants_range = (num_players.presence || 0).to_i..maximum_participants
  end

  def maximum_participants=(num_players)
    self.participants_range = minimum_participants..(num_players.presence&.to_i)
  end

  def minimum_participants
    participants_range&.begin || 0
  end

  # Postgres stores int4range canonically as [min, max + 1), so a read-back range excludes its end.
  def maximum_participants
    range_end = participants_range&.end
    return Float::INFINITY if range_end.nil? || range_end == Float::INFINITY

    participants_range.exclude_end? ? range_end - 1 : range_end
  end

  def name_with_dates
    "#{name} (#{start_time.strftime('%d/%m/%Y')} - #{end_time.strftime('%d/%m/%Y')})"
  end

  def rounds_info
    # Default fallback: single standard round
    { rounds: [{ swiss_round: :standard }], top: nil }
  end

  def number_of_swiss_rounds
    rounds.where(type: "SwissRound").count
  end

  def number_of_single_elimination_rounds
    rounds.where(type: "SingleEliminationRound").count
  end

  def self.reset_counters
    find_each do |event|
      event.reset_counters if event.respond_to?(:reset_counters)
    end
  end

  def reset_counters
    # Manually update counter caches that fixtures don't properly set
    update_columns(
      rounds_count: rounds.count,
      event_participants_count: event_participants.count
    )
    touch
  end

  # Set once from the name (never on rename, so links and QR codes keep working); "weekly-2", "weekly-3"
  # for the next events of the same name.
  def populate_slug
    return if name.blank?

    base = name.downcase.gsub(/[^a-z0-9]/, "-")
    taken = slugs_starting_with(base)
    self.slug = taken.include?(base) ? (2..).lazy.map { |n| "#{base}-#{n}" }.find { |s| taken.exclude?(s) } : base
  end

  private

  def slugs_starting_with(base)
    Event.where(slug: base).or(Event.where("slug LIKE ?", "#{Event.sanitize_sql_like(base)}-%")).pluck(:slug).to_set
  end

  # An organizer can only put their events in their own circuits.
  def circuit_of_the_same_organizer
    errors.add(:circuit, :other_organizer) if circuit && circuit.event_organizer_id != event_organizer_id
  end

  def cover_type_and_size
    return unless cover.attached?

    errors.add(:cover, :content_type) unless COVER_TYPES.include?(cover.blob.content_type)
    errors.add(:cover, :too_big) if cover.blob.byte_size > COVER_MAX_SIZE
  end

  def valid_transition
    return if transitions[state_was]&.include?(state.to_sym)

    errors.add(:state, :invalid_transition, from: state_was, to: state)
  end

  def points_locked_after_start
    return unless points_locked?

    # The match length goes with the points: results already scored would not fit another best-of.
    [*POINT_ATTRIBUTES, :match_games].each do |attribute|
      errors.add(attribute, :locked) if attribute_changed?(attribute)
    end
  end

  def apply_one_v_one_points
    return unless one_v_one?

    # Not *_changed?: a value given explicitly that equals the column (multiplayer) default, such as
    # points_win: 7, is not "changed", yet the organiser chose it and it must not become the 1v1 value.
    ONE_V_ONE_POINTS.each do |attribute, value|
      self[attribute] = value unless attribute_came_from_user?(attribute.to_s)
    end
  end

  # The format is chosen at creation only (spec §1).
  def format_locked_after_creation
    errors.add(:format, :locked) if format_changed?
  end
end
