# frozen_string_literal: true

module Organizer
  # The live preview beside the tournament form: the public event page rendered from the form's values as typed,
  # for a tournament not created yet (new) or one being edited (show). Nothing is saved. Shown in an iframe, so
  # the page may be framed by its own origin.
  class PreviewsController < OrganizerController
    require_organizer only: :new
    allow_roles :organizer, only: :show

    layout "play"
    helper_method :current_event, :current_participant, :current_round
    content_security_policy { |policy| policy.frame_ancestors :self }

    def show
      @tournament = Tournament.staffed_by(current_user).with_attached_cover.find(params.expect(:id))
      render_preview
    end

    def new
      @tournament = Tournament.new(event_organizer: current_organizer)
      render_preview
    end

    private

    def render_preview
      apply_form_values
      counts = @tournament.event_participants.playing.group(:waitlisted).count
      @enrolled_count = counts.fetch(false, 0)
      @waitlist_count = counts.fetch(true, 0)
      @decklist_locked = @tournament.points_locked?
      render "play/events/show"
    end

    def apply_form_values
      @tournament.assign_attributes(preview_params)
      @tournament.format ||= Tournament.format_for_game(@tournament.game_format) if @tournament.game_format.present?
      # The page's links and forms need a slug and an id; nothing is saved.
      @tournament.slug ||= "preview"
      @tournament.id ||= SecureRandom.uuid
    end

    # The cover (a file) and the state (set by its own buttons) cannot be previewed from the form.
    def preview_params
      params.fetch(:tournament, {}).permit(*(Tournament::SETTINGS_ATTRIBUTES - %i[cover state format]))
    end

    def current_event = @tournament
    def current_participant = nil
    def current_round = nil
  end
end
