# frozen_string_literal: true

module Admin
  # The /admin Overview numbers (spec M9 §4). Each block is cached for 60 seconds.
  class Overview
    TTL = 60.seconds
    WEEKS = 12
    MONTHS = 12

    People = Data.define(:players, :new_users, :organizers, :admins, :signups_per_week)
    Events = Data.define(:by_state, :by_format, :per_month, :average_players)
    Errors = Data.define(:unresolved, :last_day, :csp_week, :rate_limited_week)
    Result = Data.define(:people, :events, :health, :errors, :recent_audit)

    def self.call = new.call

    def call
      Result.new(people: cached(:people) { people }, events: cached(:events) { events },
                 health: cached(:health) { Health.call }, errors: cached(:errors) { errors },
                 recent_audit: cached(:recent_audit) { AuditEvent.recent.includes(:actor_user, :event).limit(10).to_a })
    end

    private

    def cached(block, &compute)
      Rails.cache.fetch("admin/overview/#{block}", expires_in: TTL, &compute)
    end

    def people
      People.new(players: Player.count, new_users: User.where(created_at: 30.days.ago..).count,
                 organizers: EventOrganizer.count, admins: User.where(admin: true).count,
                 signups_per_week: buckets(User, :created_at, :week, WEEKS))
    end

    def events
      finished = Tournament.finished.average(:event_participants_count)
      Events.new(by_state: Tournament.group(:state).count, by_format: Tournament.group(:format).count,
                 per_month: buckets(Event, :start_time, :month, MONTHS), average_players: finished&.round(1))
    end

    def errors
      week = (7.days.ago..)
      Errors.new(unresolved: ErrorEvent.unresolved.distinct.count(:fingerprint),
                 last_day: ErrorEvent.where(created_at: 24.hours.ago..).count,
                 csp_week: CspReport.where(created_at: week).count,
                 rate_limited_week: AuditEvent.for_action("rate_limited").where(created_at: week).count)
    end

    # Counts per week or month for the last `size` periods, oldest first (empty periods are 0).
    def buckets(model, column, unit, size)
      starts = (0...size).map { |ago| period_start(Time.current - ago.public_send(unit), unit) }.reverse
      counts = period_counts(model.where(column => starts.first..), "#{model.table_name}.#{column}", unit)
      starts.map { |start| counts.fetch(start, 0) }
    end

    def period_counts(scope, column, unit)
      scope.group(Arel.sql("date_trunc('#{unit}', #{column})")).count
        .transform_keys { |time| period_start(time.in_time_zone, unit) }
    end

    def period_start(time, unit) = time.public_send(:"beginning_of_#{unit}")
  end
end
