# frozen_string_literal: true

module Admin
  # /admin/organizers (M13 D17): the waiting-list signups (Pending by default, Approved, Declined) with Approve and
  # Decline, then the current organizers with Revoke. The search box narrows both lists by name or e-mail.
  class OrganizersController < BaseController
    FILTERS = %w[pending approved declined].freeze

    before_action :set_filters
    before_action :set_signup, only: %i[approve decline]

    def index
      signups = search(WaitlistSignup.public_send(@filter), "waitlist_signups.name", "waitlist_signups.email")
      @signups = signups.order(created_at: :desc).to_a
      # One query for every row's account (the e-mails are lower-case on both sides).
      @accounts = User.where(email_address: @signups.map(&:email)).index_by(&:email_address)
      load_organizers
    end

    def approve
      user = @signup.user
      return back_with(alert: t("admin.organizers.not_pending")) unless @signup.pending?
      return back_with(alert: t("admin.organizers.no_account_alert")) unless @signup.approvable?(user)

      grant(user)
      OrganizersMailer.approved(user).deliver_later
      back_with(notice: t("admin.organizers.approved_notice", email: @signup.email))
    end

    def decline
      return back_with(alert: t("admin.organizers.not_pending")) unless @signup.pending?

      @signup.update!(declined_at: Time.current)
      Audit.record("organizer_declined", subject: @signup, email: @signup.email)
      back_with(notice: t("admin.organizers.declined_notice", email: @signup.email))
    end

    # Only an organizer with no events and no circuits: destroying one would destroy them too.
    def revoke
      organizer = EventOrganizer.find(params.expect(:id))
      in_use = organizer.events.exists? || organizer.circuits.exists?
      return back_with(alert: t("admin.organizers.revoke_refused")) if in_use

      organizer.destroy!
      Audit.record("organizer_revoked", subject: organizer.user, email: organizer.user&.email_address)
      back_with(notice: t("admin.organizers.revoked_notice"))
    end

    private

    def load_organizers
      organizers = search(EventOrganizer.joins(:user).includes(:user), "users.name", "users.email_address")
      @organizers = organizers.order(created_at: :desc).to_a
      ids = @organizers.map(&:id)
      @events_counts = Event.where(event_organizer_id: ids).group(:event_organizer_id).count
      @circuits_counts = Circuit.where(event_organizer_id: ids).group(:event_organizer_id).count
    end

    # Someone who already organises keeps their EventOrganizer.
    def grant(user)
      WaitlistSignup.transaction do
        user.initialize_organizer unless user.event_organizer
        @signup.update!(approved_at: Time.current, approved_by: Current.user)
      end
      Audit.record("organizer_approved", subject: user, email: @signup.email)
    end

    # Plain strings only: ?q[]=x is dropped, not a 500; an unknown filter is Pending.
    def set_filters
      filters = params.slice(:filter, :q).permit(:filter, :q)
      @filter = filters[:filter].presence_in(FILTERS) || "pending"
      @q = filters[:q].to_s.strip
    end

    def set_signup
      @signup = WaitlistSignup.find(params.expect(:id))
    end

    def search(scope, name_column, email_column)
      return scope if @q.empty?

      q = "%#{WaitlistSignup.sanitize_sql_like(@q)}%"
      scope.where("#{name_column} ILIKE :q OR #{email_column} ILIKE :q", q: q)
    end

    # The list with the filter and search the action was taken from.
    def back_with(message)
      filters = { filter: (@filter unless @filter == "pending"), q: @q.presence }.compact
      redirect_to admin_organizers_path(**filters), **message
    end
  end
end
