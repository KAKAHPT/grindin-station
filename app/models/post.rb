# frozen_string_literal: true

# A feed post about a finished event: a player's report, the organizer's note, or the result the app writes when a
# tournament ends. One like per person; the author, the event's organizer and site admins can remove it.
class Post < ApplicationRecord
  KINDS = %w[report note result thought].freeze
  MENTION = /@([a-z0-9-]{3,30})\b/
  BODY_MAX = 1000
  REPORTS_TO_HIDE = 3
  # Plain insults and slurs (pt, en, es) a post may not contain; the admin page catches the rest through reports.
  BLOCKED_WORDS = [
    "cabrão", "cabrões", "caralho", "foda-se", "fodasse", "filho da puta", "filha da puta", "puta", "paneleiro",
    "paneleiros", "preto de merda", "retardado", "retardada", "atrasado mental",
    "fuck", "fucking", "shit", "asshole", "bitch", "cunt", "faggot", "nigger", "nigga", "retard", "retarded",
    "puto de mierda", "hijo de puta", "hija de puta", "maricón", "maricon", "gilipollas", "subnormal"
  ].freeze
  BLOCKED_PATTERN = /\b(?:#{BLOCKED_WORDS.map { |word| Regexp.escape(word) }.join('|')})\b/i

  belongs_to :user
  belongs_to :event, optional: true
  has_many :post_likes, dependent: :destroy
  has_many :post_reports, dependent: :destroy

  validates :kind, inclusion: { in: KINDS }
  validates :body, presence: true, length: { maximum: BODY_MAX }
  validates :event, presence: true, unless: :thought?
  validate :author_belongs_to_event, on: :create, if: -> { event && !result? }
  validate :body_is_civil

  after_create_commit :notify_mentions

  scope :recent, -> { order(created_at: :desc) }
  scope :visible, -> { where(hidden: false) }
  scope :in_circuit, ->(circuit) { joins(:event).where(events: { circuit_id: circuit.id }) }
  # Posts about events of one play pool (multiplayer or a 1v1 game format); thoughts have no event and stay out.
  scope :about_play, ->(play) { where(event_id: Event.with_play(play).select(:id)) }
  # Posts by the people the viewer follows, and about events run by organizers they follow.
  scope :followed_by, lambda { |viewer|
    followed = viewer.follows.select(:followed_id)
    organizers = EventOrganizer.where(user_id: followed).select(:id)
    where(user_id: followed).or(where(event_id: Event.where(event_organizer_id: organizers).select(:id)))
  }

  def result? = kind == "result"
  def thought? = kind == "thought"

  # The handles written as @handle in the body, in order, once each.
  def mentioned_handles = body.to_s.scan(MENTION).flatten.uniq

  def mentioned_users = User.where(handle: mentioned_handles).where.not(id: user_id)

  # Finished events the user played in or organizes, newest first: the ones they may post about.
  def self.postable_events_for(user)
    return Event.none unless user

    played = EventParticipant.joins(:player).where(players: { user_id: user.id }).select(:event_id)
    scope = Event.where(id: played)
    scope = scope.or(Event.where(event_organizer_id: user.event_organizer.id)) if user.event_organizer
    scope.where(state: Tournament.states[:finished]).order(start_time: :desc)
  end

  def self.can_post?(user, event) = postable_events_for(user).exists?(id: event.id)

  def removable_by?(viewer)
    return false unless viewer
    return true if viewer.admin? || viewer.id == user_id

    event.present? && viewer.event_organizer.present? && viewer.event_organizer.id == event.event_organizer_id
  end

  def liked_by?(viewer) = viewer.present? && post_likes.exists?(user_id: viewer.id)

  def reportable_by?(viewer) = viewer.present? && viewer.id != user_id && !post_reports.exists?(user_id: viewer.id)

  # The third report hides the post until an admin keeps or removes it.
  def hide_if_reported!
    update!(hidden: true) if reload.reports_count >= REPORTS_TO_HIDE && !hidden
  end

  private

  def notify_mentions
    Notify.create_for(mentioned_users.pluck(:id), kind: "mentioned", subject: self)
  end

  def body_is_civil
    text = body.to_s.dup.force_encoding(Encoding::UTF_8).scrub
    errors.add(:body, :uncivil) if text.match?(BLOCKED_PATTERN)
  end

  def author_belongs_to_event
    errors.add(:event, :not_yours) unless event && self.class.can_post?(user, event)
  end
end
