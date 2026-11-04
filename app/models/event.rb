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

  PREFERRED_POD_SIZE = 4
  SMALLER_POD_SIZE = 3
  LARGER_POD_SIZE = 5

  POINT_ATTRIBUTES = %i[points_win points_draw points_loss points_bye].freeze
  UNLOCKED_POINTS_STATES = %w[draft registration_open registration_closed].freeze
  RESULT_CONFIRMATIONS = %w[none one all].freeze
  TOP_CUT_TIMEOUT_RULES = %w[highest_seed_advances replay].freeze
  # A draft or canceled event exists only for its staff: hidden from public pages.
  HIDDEN_STATES = %w[draft canceled].freeze

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

  with_options presence: true do
    validates :state, :name, :slug, :start_time, :end_time
  end

  validates :points_win, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :points_draw, :points_loss, :points_bye, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :points_locked_after_start, on: :update
  validates :result_confirmation, inclusion: { in: RESULT_CONFIRMATIONS }
  validates :top_cut_timeout_rule, inclusion: { in: TOP_CUT_TIMEOUT_RULES }
  validates :confirmation_timeout_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 1 }

  validates :slug, uniqueness: true
  before_validation :populate_slug, if: -> { slug.blank? }

  after_update :perform_state_based_actions, if: -> { state_previously_changed? }
  after_save :geocode_address, if: -> { address_previously_changed? }

  def points_locked?
    UNLOCKED_POINTS_STATES.exclude?(state)
  end

  # Registered players who have not dropped and are off the waitlist (from the loaded association when there is one).
  def playing_participants_count
    event_participants.loaded? ? event_participants.count(&:enrolled?) : event_participants.enrolled.count
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

  def points_locked_after_start
    return unless points_locked?

    POINT_ATTRIBUTES.each do |attribute|
      errors.add(attribute, :locked) if attribute_changed?(attribute)
    end
  end
end
