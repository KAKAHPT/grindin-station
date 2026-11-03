# frozen_string_literal: true

module Organizer
  class OrganizerController < ApplicationController
    before_action :authorize_user!
    helper_method :staff_role

    # Lets only these event roles through, e.g. `allow_roles :organizer, :judge, only: :show`.
    def self.allow_roles(*roles, **)
      before_action(-> { require_role(*roles) }, **)
    end

    # Owns events or works one as staff; everything else is checked per event.
    def authorize_user!
      redirect_to root_url, alert: t("flash.alert.not_allowed") unless current_user.staff?
    end

    def require_role(*roles)
      return if roles.map(&:to_s).include?(staff_role)

      redirect_to organizer_root_url, alert: t("flash.alert.not_allowed")
    end

    # The event's owner only (not a staff organizer).
    def require_owner!
      return if role_event && role_event.event_organizer_id == current_organizer&.id

      redirect_to organizer_root_url, alert: t("flash.alert.not_allowed")
    end

    # Has an EventOrganizer of their own (creates events, circuits, leagues).
    def require_organizer!
      redirect_to organizer_root_url, alert: t("flash.alert.not_allowed") unless current_user.organizer?
    end

    def staff_role(event = role_event)
      event && current_user.staff_role_for(event)
    end

    def current_organizer
      current_user.event_organizer
    end

    private

    def role_event
      return @role_event if defined?(@role_event)

      @role_event = Event.find_by(id: params[:tournament_id] || params[:id])
    end
  end
end
