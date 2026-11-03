# frozen_string_literal: true

module Organizer
  # The event owner names who works the event and in which role.
  class StaffController < OrganizerController
    require_owner

    def index
      @tournament = load_tournament
      @staff = @tournament.event_staff.includes(:user).order(:created_at)
    end

    def create
      user = User.find_by(email_address: staff_params[:email_address]) # normalized by User
      return redirect_to(staff_path, alert: t("flash.alert.staff_user_not_found")) unless user

      redirect_to staff_path, **add_staff(user)
    end

    def destroy
      load_tournament.event_staff.find(params.expect(:id)).destroy
      redirect_to staff_path, notice: t("flash.notice.staff_removed")
    end

    private

    def add_staff(user)
      staff = load_tournament.event_staff.new(user: user, role: staff_params[:role])
      return { notice: t("flash.notice.staff_added", name: user.name) } if staff.save

      { alert: staff.errors.full_messages.to_sentence }
    end

    def load_tournament
      @load_tournament ||= Tournament.for_organizer(current_organizer).find(params.expect(:tournament_id))
    end

    def staff_path
      organizer_tournament_staff_index_path(params.expect(:tournament_id))
    end

    def staff_params
      params.expect(event_staff: %i[email_address role])
    end
  end
end
