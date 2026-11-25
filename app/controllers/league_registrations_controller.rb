# frozen_string_literal: true

# A player signs up for a league from its page, and leaves it. An open-tables league takes players while it is
# in play too. Leaving before the start removes the registration; afterwards it is a drop (the games stay).
class LeagueRegistrationsController < ApplicationController
  include PublicEvent

  before_action :load_league

  rate_limit to: 30, within: 10.minutes, only: :create, by: -> { current_user.id },
             with: -> { redirect_to league_path(params[:league_id]), alert: t("flash.alert.try_again_later") }

  { Registrations::Closed => "flash.alert.registration_closed", Registrations::Full => "flash.alert.registration_full",
    Registrations::AlreadyEnrolled => "flash.alert.already_enrolled",
    Registrations::NotInvited => "invitations.not_invited" }.each do |error, key|
    rescue_from(error) { redirect_to back, alert: t(key) }
  end

  def create # rubocop:disable Metrics/AbcSize
    return redirect_to(back, alert: t("flash.alert.no_player")) if current_user.player.nil?
    return redirect_to(back, alert: t("leagues.registration.accept_terms")) unless params[:accepted_terms] == "1"

    participant = Registrations::Enroll.call(event: @league, player: current_user.player)
    notice =
      if participant.waitlisted?
        t("flash.notice.registration_waitlisted", position: participant.waitlist_position)
      else
        t("leagues.registration.notices.registered")
      end
    redirect_to back, notice: notice
  end

  def destroy # rubocop:disable Metrics/AbcSize
    participant = current_user.player && @league.event_participants.find_by(player: current_user.player)
    return redirect_to(back, alert: t("flash.alert.not_registered")) if participant.nil? || participant.dropped?

    Leagues::Leave.call(league: @league, participant: participant, by: current_user)
    Turbo::StreamsChannel.broadcast_refresh_later_to(@league, :tables)
    redirect_to back, notice: t("leagues.registration.notices.left")
  rescue Leagues::Tables::NotAllowed => e
    redirect_to back, alert: t("leagues.tables.not_allowed.#{e.message}")
  end

  private

  def load_league
    @league = ensure_public!(League.find(params.expect(:league_id)))
  end

  def back = league_path(@league, locale: params[:locale])
end
