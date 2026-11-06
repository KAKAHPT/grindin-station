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
      current_user.banner = params.dig(:user, :banner) if params.dig(:user, :banner).present?

      if @organizer.valid? && current_user.valid? && EventOrganizer.transaction do
        @organizer.save! && current_user.save!
      end
        redirect_to edit_organizer_about_path, notice: t("organizer.about.saved")
      else
        @organizer.errors.merge!(current_user.errors) if current_user.errors.any?
        render :edit, status: :unprocessable_content
      end
    end

    private

    def about_params
      params.expect(event_organizer: [:description, :location, { links: EventOrganizer::LINKS }])
    end
  end
end
