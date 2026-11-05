# frozen_string_literal: true

module Admin
  # /admin/audit filters (GET params): action_name, user (e-mail contains), event (name contains), from / to dates.
  class AuditSearch
    def self.call(params) = new(params).call

    def initialize(params)
      @params = params
    end

    def call
      scope = AuditEvent.recent.includes(:actor_user, :event)
      scope = scope.for_action(@params[:action_name]) if @params[:action_name].present?
      scope = contains(scope, :actor_user, User.arel_table[:email_address], @params[:user])
      scope = contains(scope, :event, Event.arel_table[:name], @params[:event])
      dated(scope)
    end

    private

    def contains(scope, association, column, text)
      return scope if text.blank?

      scope.joins(association).where(column.matches("%#{AuditEvent.sanitize_sql_like(text.strip)}%"))
    end

    def dated(scope)
      from = date(@params[:from])&.beginning_of_day
      to = date(@params[:to])&.end_of_day
      from || to ? scope.where(created_at: from..to) : scope
    end

    def date(value)
      Date.iso8601(value) if value.present?
    rescue Date::Error
      nil
    end
  end
end
