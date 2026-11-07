# frozen_string_literal: true

module Registrations
  # The Add player dialog's lookup: accounts whose name (mode "name") or e-mail (mode "email") contains the typed
  # text, up to LIMIT, each with whether that player is already in the event. Name mode shows only the first letter
  # and the domain of the e-mail, so a roster cannot be used to harvest addresses; e-mail mode shows the address the
  # organizer is already typing.
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
      column = @mode == "email" ? "email_address" : "name"
      User.where(anonymized_at: nil).joins(:player).includes(:player)
        .where("users.#{column} ILIKE ?", "%#{User.sanitize_sql_like(@text)}%").order(:name).limit(LIMIT)
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
