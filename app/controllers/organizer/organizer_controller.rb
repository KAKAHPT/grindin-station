# frozen_string_literal: true

module Organizer
  class OrganizerController < ApplicationController
    # Fail closed: an action runs only if a macro below declared how it is authorized.
    class_attribute :authorization_rules, instance_accessor: false, default: []

    before_action :authorize_user!
    before_action :require_declared_action!
    helper_method :staff_role

    class << self
      # Lets only these event roles through, e.g. `allow_roles :organizer, :judge, only: :show`.
      def allow_roles(*roles, **)
        declare_authorized(**)
        before_action(-> { require_role(*roles) }, **)
      end

      def require_owner(**)
        declare_authorized(**)
        before_action(:require_owner!, **)
      end

      def require_organizer(**)
        declare_authorized(**)
        before_action(:require_organizer!, **)
      end

      # Open to anyone let in by authorize_user! (each action scopes its own data).
      def public_actions(*actions)
        declare_authorized(only: actions)
      end

      def action_declared?(action)
        authorization_rules.any? do |only, except|
          (only.nil? || only.include?(action)) && except.exclude?(action)
        end
      end

      private

      def declare_authorized(only: nil, except: nil)
        self.authorization_rules += [[only && Array(only).map(&:to_s), Array(except).map(&:to_s)]]
      end
    end

    # Owns events or works one as staff; everything else is checked per event.
    def authorize_user!
      redirect_to root_url, alert: t("flash.alert.not_allowed") unless current_user.staff?
    end

    def require_declared_action!
      return if self.class.action_declared?(action_name)

      redirect_to organizer_root_url, alert: t("flash.alert.not_allowed")
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

      # Path parameters only: a query or body tournament_id must not pick the event checked.
      path = request.path_parameters
      @role_event = Event.find_by(id: path[:tournament_id] || path[:id])
    end
  end
end
