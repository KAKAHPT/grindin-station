# frozen_string_literal: true

module Admin
  # /admin/errors: unresolved errors by fingerprint (with the latest occurrence), CSP reports of the last 30 days
  # and rate-limit hits of the last 7 days.
  module ErrorGroups
    Group = Data.define(:fingerprint, :count, :last_seen_at, :latest)
    LIMIT = 100

    def self.unresolved
      groups = ErrorEvent.unresolved.grouped.limit(LIMIT).to_a
      latest = latest_of(groups.map(&:fingerprint))
      groups.map do |group|
        Group.new(fingerprint: group.fingerprint, count: group.occurrences, last_seen_at: group.last_seen_at,
                  latest: latest[group.fingerprint])
      end
    end

    # fingerprint => its newest unresolved occurrence.
    def self.latest_of(fingerprints)
      ErrorEvent.unresolved.where(fingerprint: fingerprints).select("DISTINCT ON (fingerprint) error_events.*")
        .order(:fingerprint, created_at: :desc).index_by(&:fingerprint)
    end

    # [[directive, blocked_uri, count, last_seen_at], ...], most frequent first.
    def self.csp_reports
      CspReport.where(created_at: 30.days.ago..).group(:violated_directive, :blocked_uri)
        .order(Arel.sql("COUNT(*) DESC")).limit(LIMIT)
        .pluck(:violated_directive, :blocked_uri, Arel.sql("COUNT(*)"), Arel.sql("MAX(created_at)"))
    end

    # [["controller#action", count], ...], most frequent first.
    def self.rate_limits
      AuditEvent.for_action("rate_limited").where(created_at: 7.days.ago..)
        .group(Arel.sql("data->>'controller'"), Arel.sql("data->>'action'"))
        .order(Arel.sql("COUNT(*) DESC")).limit(LIMIT)
        .pluck(Arel.sql("data->>'controller'"), Arel.sql("data->>'action'"), Arel.sql("COUNT(*)"))
        .map { |controller, action, count| ["#{controller}##{action}", count] }
    end
  end
end
