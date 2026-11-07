# frozen_string_literal: true

module Registrations
  # The Add player dialog's lookup, up to LIMIT rows, each with whether that player is already in the event.
  # Mode "email" matches the full, normalised address only (the organizer must know it; substrings would let a
  # roster harvest the whole directory). Mode "name" matches the name by substring, shows only the first letter and
  # the domain of the e-mail, and leaves private profiles out unless they are already in the event.
  class PlayerSearch
    LIMIT = 8
    MIN_LENGTH = { "name" => 2, "email" => 3 }.freeze

    def initialize(event, mode:, text:)
      @event = event
      @mode = MIN_LENGTH.key?(mode) ? mode : "name"
      @text = text.to_s.strip
    end

    def call
      return [] if @text.length < MIN_LENGTH[@mode]

      in_event = @event.event_participants.pluck(:player_id).to_set
      users.map { |user| row(user, in_event) }
    end

    private

    def users
      scope = User.where(anonymized_at: nil).joins(:player).includes(:player)
      return scope.where(email_address: @text.downcase).limit(1) if @mode == "email"

      scope.where("users.name ILIKE ?", "%#{User.sanitize_sql_like(@text)}%")
        .where("users.visibility <> 'private' OR players.id IN (?)", in_event_ids).order(:name).limit(LIMIT)
    end

    def in_event_ids
      @in_event_ids ||= @event.event_participants.pluck(:player_id)
    end

    def row(user, in_event)
      { player_id: user.player.id, name: user.name, handle: user.handle, email: shown_email(user),
        in_event: in_event.include?(user.player.id) }
    end

    def shown_email(user)
      return user.email_address if @mode == "email"

      local, domain = user.email_address.split("@", 2)
      "#{local.first}…@#{domain}"
    end
  end
end
