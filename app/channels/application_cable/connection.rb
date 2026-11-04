# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    # Visitors connect too (public pairings): every stream is subscribed by its signed name, which only
    # the page that may show it carries, so the connection itself needs no identity.
    def connect
      set_current_user
    end

    private

    # An expired session (Session::LIFETIME) identifies nobody: the socket connects as a visitor.
    def set_current_user
      session = Session.find_by(id: cookies.signed[:session_id])
      self.current_user = session.user if session && !session.expired?
    end
  end
end
