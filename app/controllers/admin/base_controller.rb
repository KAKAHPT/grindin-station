# frozen_string_literal: true

module Admin
  # Site-admin area. Anyone who is not an admin (signed in or not) gets a plain 404, so /admin does not reveal itself.
  class BaseController < ApplicationController
    allow_unauthenticated_access
    before_action :require_admin

    private

    def require_admin
      resume_session
      head :not_found unless current_user&.admin?
    end
  end
end
