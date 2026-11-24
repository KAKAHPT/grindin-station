# frozen_string_literal: true

module Organizer
  # The invitations of an invitation-only event: the organizer looks accounts up by name (or by the full
  # e-mail), invites them (an e-mail with the event's link goes out) and can take an invitation back.
  class InvitationsController < OrganizerController
    allow_roles :organizer

    rate_limit to: 120, within: 1.hour, only: :create, by: -> { current_user.id },
               with: -> { redirect_to invitations_path, alert: t("flash.alert.try_again_later") }

    def index
      @tournament = load_tournament
      @q = params[:q].to_s.strip
      @results = search(@q)
      @user_ids = Player.where(id: @results.pluck(:player_id)).pluck(:id, :user_id).to_h
      load_invited
    end

    # Inviting again sends the e-mail again.
    def create
      user = invitable_user
      return redirect_to(invitations_path, alert: t("invitations.no_account")) if user.nil?

      again = invite(user)
      redirect_to invitations_path, notice: t(again ? "invitations.sent_again" : "invitations.sent", name: user.name)
    end

    def destroy
      invitation = load_tournament.event_invitations.find(params.expect(:id))
      invitation.destroy!
      redirect_to invitations_path, notice: t("invitations.removed", name: invitation.user.name)
    end

    private

    def load_invited
      @invitations = @tournament.event_invitations.includes(:user).order(created_at: :desc)
      @registered = @tournament.event_participants.joins(:player).pluck("players.user_id").to_set
    end

    def search(text)
      Registrations::PlayerSearch.new(@tournament, mode: text.include?("@") ? "email" : "name", text: text).call
    end

    # Saves the invitation and sends its e-mail; true when the user was already invited.
    def invite(user)
      invitation = load_tournament.event_invitations.find_or_initialize_by(user: user)
      again = invitation.persisted?
      invitation.update!(invited_by: current_user)
      InvitationsMailer.invited(invitation).deliver_later
      again
    end

    def invitable_user
      user = Player.find_by(id: params.expect(:player_id))&.user
      user unless user&.anonymized_at
    end

    def load_tournament
      @load_tournament ||= Tournament.staffed_by(current_user).with_attached_cover.find(params.expect(:tournament_id))
    end

    def invitations_path
      organizer_tournament_invitations_path(params.expect(:tournament_id), q: params[:q].presence)
    end
  end
end
