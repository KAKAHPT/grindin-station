# frozen_string_literal: true

module Admin
  # The site's growth for the operator's desktop assistant (JARVIS), read by GET /api/v1/admin/summary.
  # Read-only, never cached. Accounts carry no e-mail; removed (anonymized) accounts are left out.
  class Summary
    WEEKS = Overview::WEEKS
    REQUESTS = 100
    ACCOUNTS = 50
    TOURNAMENTS = 50

    def self.call = new.call

    def call
      { generated_at: Time.current.iso8601, totals: totals, weekly: weekly, requests: requests,
        accounts: accounts, tournaments: tournaments }
    end

    private

    def totals
      { players: Player.count, users: User.where(anonymized_at: nil).count, organizers: EventOrganizer.count,
        tournaments: Tournament.count, tournaments_running: Tournament.ongoing.count,
        errors_unresolved: ErrorEvent.unresolved.distinct.count(:fingerprint),
        requests_pending: WaitlistSignup.pending.count }
    end

    def weekly
      overview = Overview.new
      accounts = overview.buckets(User, :created_at, :week, WEEKS)
      requests = overview.buckets(WaitlistSignup, :created_at, :week, WEEKS)
      Overview.period_starts(:week, WEEKS).each_with_index.map do |start, index|
        { week_start: start.to_date.iso8601, accounts: accounts[index], requests: requests[index] }
      end
    end

    def requests
      signups = WaitlistSignup.order(created_at: :desc).limit(REQUESTS).to_a
      # One query for every row's account (the e-mails are lower-case on both sides).
      with_account = User.where(email_address: signups.map(&:email)).pluck(:email_address).to_set
      signups.map do |signup|
        { id: signup.id, name: signup.name, email: signup.email, status: status(signup),
          created_at: signup.created_at.iso8601, has_account: with_account.include?(signup.email) }
      end
    end

    # A revoked organizer's signup has both cleared approval and a decline, so the decline wins.
    def status(signup)
      return "declined" if signup.declined_at
      return "approved" if signup.approved_at

      "pending"
    end

    def accounts
      User.where(anonymized_at: nil).order(created_at: :desc).limit(ACCOUNTS)
        .pluck(:id, :name, :handle, :created_at)
        .map { |id, name, handle, created| { id: id, name: name, handle: handle, created_at: created.iso8601 } }
    end

    def tournaments
      Tournament.includes(event_organizer: :user).order(created_at: :desc).limit(TOURNAMENTS).map do |event|
        { slug: event.slug, name: event.name, state: event.state, format: event.format,
          players: event.event_participants_count, start_time: event.start_time&.iso8601,
          organizer: event.event_organizer&.user&.display_name }
      end
    end
  end
end
