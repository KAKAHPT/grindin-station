# frozen_string_literal: true

class User < ApplicationRecord # rubocop:disable Metrics/ClassLength
  VISIBILITIES = %w[public participants private].freeze
  HANDLE_FORMAT = /\A[a-z0-9-]{3,30}\z/
  AVATAR_TYPES = %w[image/jpeg image/png image/webp].freeze
  AVATAR_MAX_SIZE = 2.megabytes
  HANDLE_TRIES = 3

  attribute :organizer, :boolean, default: false

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :identities, dependent: :destroy
  has_one_attached :avatar do |attachable|
    attachable.variant :thumb, resize_to_fill: [96, 96]
    attachable.variant :profile, resize_to_fill: [256, 256]
  end

  before_validation :assign_handle, on: :create, if: -> { handle.blank? }

  after_create :initialize_player, if: -> { !organizer }
  after_create :initialize_organizer, if: -> { organizer }
  # An anonymised user keeps its player key so the player stays linked to its event history.
  after_update :update_key, if: lambda {
    anonymized_at.nil? && (email_address_previously_changed? || name_previously_changed?)
  }

  has_one :player, dependent: :nullify
  has_one :event_organizer, dependent: :nullify
  has_many :event_staff, class_name: "EventStaff", dependent: :destroy
  has_many :notifications, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :country, with: ->(c) { c.strip.upcase.presence }

  validates :password, length: { minimum: 8 }, allow_nil: true
  validates :email_address, presence: true, uniqueness: true
  validates :email_address, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :name, presence: true
  validates :handle, format: { with: HANDLE_FORMAT }, uniqueness: true, allow_nil: true
  validates :handle, presence: true, unless: :anonymized?
  validates :visibility, inclusion: { in: VISIBILITIES }
  validates :country, format: { with: /\A[A-Z]{2}\z/ }, allow_nil: true
  validates :bio, length: { maximum: 500 }
  validate :avatar_type_and_size

  # A retry has to wrap the whole save (callbacks run inside it), so these override save itself.
  def save(**) # rubocop:disable Rails/ActiveRecordOverride
    with_handle_retry { super }
  end

  def save!(**)
    with_handle_retry { super }
  end

  def anonymized?
    anonymized_at.present?
  end

  # Unlinking a sign-in must leave a way in: a password the user chose, or another linked identity.
  def can_unlink_identity?
    password_set || identities.size > 1
  end

  # public: anyone; participants: the user or a signed-in player of one of their events; private: the user only.
  def profile_visible_to?(viewer)
    return false if anonymized?
    return true if visibility == "public"
    return false if viewer.nil?
    return true if viewer.id == id

    visibility == "participants" && shares_event_with?(viewer)
  end

  def unread_notifications_count
    notifications.unread.count
  end

  def display_name
    anonymized? ? I18n.t("accounts.removed_player") : name
  end

  # The separator keeps "a@x.com" + "bc" and "a@x.comb" + "c" apart.
  def compute_key
    Digest::MD5.hexdigest("#{email_address}\0#{name}")
  end

  # Adopts an unowned player with this key (one created before the user signed up); a player that
  # belongs to someone else is never taken over, the new user gets its own.
  def initialize_player
    return if player

    key = compute_key
    unowned = Player.find_by(key: key, user_id: nil)
    self.player = unowned || Player.new(key: free_key(key))
    player.save
  end

  def initialize_organizer
    EventOrganizer.create!(user: self)
  end

  def update_key
    player&.update(key: free_key(compute_key))
  end

  def organizer?(event = nil)
    event_organizer.present? && (event.blank? || event_organizer.events.include?(event))
  end

  # "organizer" for the event's owner, else the staff row's role, else nil.
  def staff_role_for(event)
    return "organizer" if event.event_organizer&.user_id == id

    event_staff.find_by(event: event)&.role
  end

  # Owns events or works at least one as staff: may enter the organizer area.
  def staff?
    organizer? || event_staff.exists?
  end

  def player?(event = nil)
    player.present? && (event.blank? || player.events.include?(event))
  end

  private

  # "Fábio Batista" -> "fabio-batista", then "fabio-batista-2", "-3"... until no other user has it.
  # The name as a handle, with -2, -3, … when taken (one query); handles that lost a race are skipped.
  def assign_handle
    base = handle_base
    taken = User.where(handle: base).or(User.where("handle LIKE ?", "#{base}-%")).pluck(:handle).to_set
    self.handle = first_free_handle(base, taken.merge(@lost_handles.to_a))
    @handle_generated = true
  end

  def handle_base
    base = name.to_s.parameterize.tr("_", "-").first(26).delete_suffix("-")
    base.length < 3 ? "player" : base
  end

  def first_free_handle(base, taken)
    return base unless taken.include?(base)

    (2..).lazy.map { |n| "#{base}-#{n}" }.find { |candidate| taken.exclude?(candidate) }
  end

  # Two sign-ups with the same name can both pass validation; the one whose insert hits the unique
  # index retries with the next suffix, at most HANDLE_TRIES times. The savepoint keeps an outer
  # transaction usable after the failed insert.
  def with_handle_retry(&block)
    return yield unless new_record?

    tries = 0
    begin
      self.class.transaction(requires_new: true, &block)
    rescue ActiveRecord::RecordNotUnique => e
      raise unless @handle_generated && e.message.include?("index_users_on_handle") && (tries += 1) < HANDLE_TRIES

      (@lost_handles ||= []) << handle
      self.handle = nil
      retry
    end
  end

  # The key, or the key with a random suffix when another player already holds it.
  def free_key(key)
    Player.where(key: key).where.not(id: player&.id).exists? ? "#{key}-#{SecureRandom.hex(4)}" : key
  end

  def shares_event_with?(other)
    events_of = ->(user) { EventParticipant.joins(:player).where(players: { user_id: user.id }).select(:event_id) }
    events_of.call(other).exists?(event_id: events_of.call(self))
  end

  def avatar_type_and_size
    return unless avatar.attached?

    errors.add(:avatar, :content_type) unless AVATAR_TYPES.include?(avatar.blob.content_type)
    errors.add(:avatar, :too_big) if avatar.blob.byte_size > AVATAR_MAX_SIZE
  end
end
