# frozen_string_literal: true

module Admin
  # /admin/accounts: every account, newest first, with a search by name, e-mail or handle (the list behind the
  # Overview's sign-up numbers). Per account: send the confirmation e-mail again, block or unblock the sign-in, and
  # delete (the same anonymisation as the owner's own "Delete account": results stay under "Removed player").
  # Admins and deleted accounts cannot be blocked or deleted here.
  class AccountsController < BaseController
    PER_PAGE = 50

    before_action :set_account, except: :index
    before_action :refuse_protected, only: %i[block destroy]

    def index
      @q = params.permit(:q)[:q].to_s.strip.presence
      @total = User.count
      @accounts = search(User.includes(:event_organizer)).order(created_at: :desc).page(params[:page]).per(PER_PAGE)
    end

    def resend_confirmation
      return back_with(alert: t("admin.accounts.already_confirmed")) if @account.confirmed?

      ConfirmationsMailer.confirm(@account).deliver_later
      Audit.record(:confirmation_resent, subject: @account)
      back_with(notice: t("admin.accounts.confirmation_sent", email: @account.email_address))
    end

    # Ends the account's sessions too, so the block takes effect at once.
    def block
      @account.update_columns(blocked_at: Time.current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      @account.sessions.destroy_all
      Audit.record("account_blocked", subject: @account, email: @account.email_address)
      back_with(notice: t("admin.accounts.blocked_notice", email: @account.email_address))
    end

    def unblock
      @account.update_columns(blocked_at: nil, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      Audit.record("account_unblocked", subject: @account, email: @account.email_address)
      back_with(notice: t("admin.accounts.unblocked_notice", email: @account.email_address))
    end

    def destroy
      email = @account.email_address
      Audit.record("account_deleted_by_admin", subject: @account, email: email)
      Accounts::Anonymize.call(user: @account)
      back_with(notice: t("admin.accounts.deleted_notice", email: email))
    end

    private

    def set_account
      @account = User.find(params.expect(:id))
    end

    def refuse_protected
      back_with(alert: t("admin.accounts.protected")) if @account.admin? || @account.anonymized?
    end

    # The list with the search and page the row was on.
    def back_with(message)
      redirect_to admin_accounts_path(q: params[:q].presence, page: params[:page].presence), **message
    end

    def search(scope)
      return scope unless @q

      q = "%#{User.sanitize_sql_like(@q)}%"
      scope.where("users.name ILIKE :q OR users.email_address ILIKE :q OR users.handle ILIKE :q", q: q)
    end
  end
end
