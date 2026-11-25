# frozen_string_literal: true

module Admin
  # /admin/accounts: every account, newest first, with a search by name, e-mail or handle. Read only: it is the list
  # behind the Overview's sign-up numbers.
  class AccountsController < BaseController
    PER_PAGE = 50

    def index
      @q = params.permit(:q)[:q].to_s.strip.presence
      @total = User.count
      @accounts = search(User.includes(:event_organizer)).order(created_at: :desc).page(params[:page]).per(PER_PAGE)
    end

    private

    def search(scope)
      return scope unless @q

      q = "%#{User.sanitize_sql_like(@q)}%"
      scope.where("users.name ILIKE :q OR users.email_address ILIKE :q OR users.handle ILIKE :q", q: q)
    end
  end
end
