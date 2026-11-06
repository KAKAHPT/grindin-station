# frozen_string_literal: true

module Organizer
  # /organizer/about: the organizer's public card (description, location, links, banner) shown on /o/:handle.
  class AboutController < OrganizerController
    require_organizer
    layout "application"

    def edit
      @organizer = current_organizer
    end

    def update
      @organizer = current_organizer
      @organizer.assign_attributes(about_params)
      banner = params.dig(:user, :banner)
      current_user.banner = banner if banner.present?

      if save_about
        redirect_to edit_organizer_about_path, notice: t("organizer.about.saved")
      else
        render :edit, status: :unprocessable_content
      end
    end

    private

    # Both records or neither; the user's errors (a bad banner) join the organizer's for the form.
    def save_about
      EventOrganizer.transaction { @organizer.save! && current_user.save! }
    rescue ActiveRecord::RecordInvalid
      @organizer.errors.merge!(current_user.errors) if current_user.errors.any?
      false
    end

    def about_params
      params.expect(event_organizer: [:description, :location, { links: EventOrganizer::LINKS }])
    end
  end
end
